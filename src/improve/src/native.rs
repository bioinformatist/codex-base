use crate::{Result, contracts::*, ensure};
use nix::{
    errno::Errno,
    fcntl::{FcntlArg, OFlag, fcntl},
    poll::{PollFd, PollFlags, PollTimeout, poll},
};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    io::{self, BufRead, BufReader, Write},
    os::fd::AsFd,
    path::Path,
    process::{Child, ChildStdin, Command, ExitStatus, Stdio},
    sync::mpsc::{self, Receiver, Sender},
    thread,
    time::{Duration, Instant},
};

pub enum Input {
    Command(Value),
    Native(Value),
    Lost(String),
}
pub fn emit(value: &Value) -> Result<()> {
    let mut out = std::io::stdout().lock();
    serde_json::to_writer(&mut out, value)?;
    writeln!(out)?;
    out.flush()?;
    Ok(())
}
fn lines(
    reader: impl std::io::Read + Send + 'static,
    tx: Sender<Input>,
    controller: bool,
) -> thread::JoinHandle<bool> {
    thread::spawn(move || {
        for line in BufReader::new(reader).lines() {
            let input = match line {
                Ok(line) => match strict_json(line.as_bytes()) {
                    Ok(v) => {
                        if controller {
                            Input::Command(v)
                        } else {
                            Input::Native(v)
                        }
                    }
                    Err(e) => Input::Lost(format!(
                        "invalid {} JSON: {e}",
                        if controller { "controller" } else { "native" }
                    )),
                },
                Err(e) => Input::Lost(e.to_string()),
            };
            if tx.send(input).is_err() {
                return false;
            }
        }
        let _ = tx.send(Input::Lost(
            if controller {
                "controller disconnected"
            } else {
                "App Server connection lost"
            }
            .into(),
        ));
        true
    })
}

#[derive(Default)]
pub struct TurnResult {
    pub status: String,
    pub completed: bool,
    pub text: String,
    pub text_error: Option<String>,
    pub error: Value,
    pub usage: Value,
}

#[derive(PartialEq, serde::Serialize)]
#[serde(rename_all = "camelCase")]
pub struct FrozenThread {
    root: String,
    parent_thread_id: Option<String>,
    session_id: String,
    cwd: String,
    pub turns: BTreeMap<String, String>,
    loaded: bool,
}

#[derive(PartialEq)]
enum FreezeState {
    Unverified,
    Pending,
    Confirmed,
}

/// A connected official App Server, with only the native facts needed for acceptance.
pub struct Native {
    child: Child,
    stdout_reader: thread::JoinHandle<bool>,
    stdin: Option<ChildStdin>,
    rx: Receiver<Input>,
    commands: VecDeque<Value>,
    next_id: u64,
    pub pending_turn: Option<(String, String)>,
    submitted_turns: BTreeSet<String>,
    pub turns: BTreeMap<(String, String), TurnResult>,
    pub usage: BTreeMap<String, Value>,
    unloaded: BTreeMap<String, bool>,
    questions: BTreeSet<String>,
    pub roots: BTreeMap<String, Value>,
    frozen_members: BTreeMap<String, (String, FreezeState)>,
    archive_deadline: Option<Instant>,
    archive_members: BTreeSet<String>,
}
impl Native {
    pub fn start(
        argv: &[String],
        cwd: &Path,
        vars: &BTreeMap<String, String>,
        controller: bool,
    ) -> Result<Self> {
        let mut child = Command::new(&argv[0])
            .args(&argv[1..])
            .current_dir(cwd)
            .envs(vars)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|e| format!("cannot start selected App Server: {e}"))?;
        let stdin = child.stdin.take();
        let (tx, rx) = mpsc::channel();
        let stdout_reader = lines(
            child.stdout.take().ok_or("missing native stdout")?,
            tx.clone(),
            false,
        );
        if controller {
            let _ = lines(std::io::stdin(), tx, true);
        }
        let mut client = Self {
            child,
            stdout_reader,
            stdin,
            rx,
            commands: VecDeque::new(),
            next_id: 0,
            pending_turn: None,
            submitted_turns: BTreeSet::new(),
            turns: BTreeMap::new(),
            usage: BTreeMap::new(),
            unloaded: BTreeMap::new(),
            questions: BTreeSet::new(),
            roots: BTreeMap::new(),
            frozen_members: BTreeMap::new(),
            archive_deadline: None,
            archive_members: BTreeSet::new(),
        };
        client.rpc("initialize",json!({"clientInfo":{"name":"codex_improve","version":"0.20.0"},"capabilities":{"experimentalApi":true}}))?;
        client.send(&json!({"method":"initialized"}))?;
        Ok(client)
    }
    fn send(&mut self, v: &Value) -> Result<()> {
        let stdin = self.stdin.as_mut().ok_or("native connection is closed")?;
        if let Some(deadline) = self.archive_deadline {
            let mut line = serde_json::to_vec(v)?;
            line.push(b'\n');
            let mut bytes = line.as_slice();
            while !bytes.is_empty() {
                remaining(deadline)?;
                match stdin.write(bytes) {
                    Ok(0) => return Err("native pipe stopped accepting data".into()),
                    Ok(n) => bytes = &bytes[n..],
                    Err(e) if e.kind() == io::ErrorKind::WouldBlock => {
                        let mut fd = [PollFd::new(stdin.as_fd(), PollFlags::POLLOUT)];
                        match poll(&mut fd, PollTimeout::try_from(remaining(deadline)?)?) {
                            Ok(_) | Err(Errno::EINTR) => {}
                            Err(e) => return Err(e.into()),
                        }
                    }
                    Err(e) if e.kind() == io::ErrorKind::Interrupted => {}
                    Err(e) => return Err(e.into()),
                }
            }
            return Ok(());
        }
        serde_json::to_writer(&mut *stdin, v)?;
        writeln!(stdin)?;
        stdin.flush()?;
        Ok(())
    }
    pub fn rpc(&mut self, method: &str, params: Value) -> Result<Value> {
        rpc_result(method, self.rpc_reply(method, params)?)
    }
    fn rpc_reply(&mut self, method: &str, params: Value) -> Result<Value> {
        if method == "turn/start" {
            self.pending_turn = None;
            self.submitted_turns
                .insert(string(&params["threadId"])?.into());
        }
        self.next_id += 1;
        let id = self.next_id;
        self.send(&json!({"id":id,"method":method,"params":params}))?;
        loop {
            let input = if let Some(deadline) = self.archive_deadline {
                let received = self.rx.recv_timeout(remaining(deadline)?);
                remaining(deadline)?;
                received?
            } else {
                self.rx.recv()?
            };
            match input {
                Input::Lost(reason) => return Err(reason.into()),
                Input::Command(v) => self.commands.push_back(v),
                Input::Native(v) => {
                    if v.get("method").is_none() && v["id"] == id {
                        if method == "turn/start"
                            && v.get("error").is_none()
                            && v.get("result").is_some()
                        {
                            self.pending_turn = None;
                        }
                        return Ok(v);
                    }
                    if method == "turn/start"
                        && v["method"] == "turn/started"
                        && v["params"]["threadId"] == params["threadId"]
                    {
                        self.pending_turn = Some((
                            string(&params["threadId"])?.into(),
                            string(&v["params"]["turn"]["id"])?.into(),
                        ));
                    }
                    self.observe(v)?;
                }
            }
        }
    }
    pub fn next(&mut self) -> Result<Option<Value>> {
        if let Some(v) = self.commands.pop_front() {
            return Ok(Some(v));
        }
        match self.rx.recv()? {
            Input::Command(v) => Ok(Some(v)),
            Input::Native(v) => {
                self.observe(v)?;
                Ok(None)
            }
            Input::Lost(reason) => Err(reason.into()),
        }
    }
    fn observe(&mut self, v: Value) -> Result<()> {
        let method = string(&v["method"])?;
        let p = &v["params"];
        if self.archive_deadline.is_some() {
            let id = p["threadId"].as_str().unwrap_or_default();
            let unloaded = method == "thread/closed"
                || method == "thread/status/changed" && p["status"]["type"] == "notLoaded";
            ensure(
                v.get("id").is_none()
                    && method != "model/rerouted"
                    && (!unloaded || self.archive_members.contains(id))
                    && !(self.archive_members.contains(id)
                        && (method == "turn/started"
                            || method == "thread/status/changed"
                                && p["status"]["type"] == "active")),
                "unexpected native activity during archive",
            )?;
            return Ok(());
        }
        if v.get("id").is_some() {
            if method == "item/tool/requestUserInput" {
                self.questions.insert(v["id"].to_string());
                emit(&json!({"question":v}))?;
            } else {
                // A client never grants new permissions or approves external effects.
                self.send(&json!({"id":v["id"],"error":{"code":-32601,"message":"Improve does not authorize this server request"}}))?;
            }
            return Ok(());
        }
        if matches!(method, "turn/started" | "turn/completed")
            || method == "thread/status/changed" && p["status"]["type"] == "active"
        {
            let id = string(&p["threadId"])?;
            if let Some((_, state)) = self.frozen_members.get_mut(id) {
                // Resuming a child cannot erase an unload that preceded confirmed freeze.
                if *state == FreezeState::Confirmed
                    && method != "turn/completed"
                    && self.unloaded.get(id) == Some(&true)
                {
                    self.unloaded.remove(id);
                }
                *state = FreezeState::Unverified;
            }
        }
        match method {
            "model/rerouted" => {
                return Err("native model changed; no fallback is authorized".into());
            }
            "thread/closed" | "thread/status/changed"
                if method == "thread/closed" || p["status"]["type"] == "notLoaded" =>
            {
                let id = string(&p["threadId"])?;
                ensure(
                    !self.roots.contains_key(id),
                    "loaded task root lost; a new budget root requires authorization",
                )?;
                ensure(
                    self.frozen_members
                        .get(id)
                        .is_none_or(|(_, state)| *state == FreezeState::Confirmed),
                    "a descendant unloaded before its freeze was confirmed",
                )?;
                *self.unloaded.entry(id.into()).or_default() |= method == "thread/closed";
            }
            "thread/tokenUsage/updated" => {
                self.usage
                    .insert(string(&p["threadId"])?.into(), p["tokenUsage"].clone());
                let key = (string(&p["threadId"])?.into(), string(&p["turnId"])?.into());
                self.turns.entry(key).or_default().usage = p["tokenUsage"].clone();
            }
            "turn/started" | "turn/completed" => {
                let key = (
                    string(&p["threadId"])?.into(),
                    string(&p["turn"]["id"])?.into(),
                );
                let turn = self.turns.entry(key).or_default();
                let status = string(&p["turn"]["status"])?;
                ensure(
                    ["inProgress", "completed", "interrupted", "failed"].contains(&status),
                    "unknown native turn status",
                )?;
                turn.status = status.into();
                turn.completed = method == "turn/completed";
                turn.error = p["turn"]["error"].clone();
                if let Some(items) = p["turn"]["items"].as_array() {
                    for item in items {
                        final_text(turn, item)?;
                    }
                }
            }
            "item/completed" if p["item"]["type"] == "agentMessage" => {
                let key = (string(&p["threadId"])?.into(), string(&p["turnId"])?.into());
                final_text(self.turns.entry(key).or_default(), &p["item"])?;
            }
            _ => {}
        }
        if [
            "turn/started",
            "turn/completed",
            "thread/tokenUsage/updated",
            "thread/status/changed",
        ]
        .contains(&method)
        {
            emit(
                &json!({"event":method,"threadId":p["threadId"],"turnId":p.get("turnId").unwrap_or(&p["turn"]["id"]),"status":p["turn"]["status"],"usage":p["tokenUsage"]}),
            )?;
        }
        Ok(())
    }
    pub fn answer(&mut self, request: &Value, answers: &Value) -> Result<()> {
        ensure(
            self.questions.remove(&request.to_string()),
            "no pending native question with this ID",
        )?;
        ensure(answers.is_object(), "answers must be an object")?;
        self.send(&json!({"id":request,"result":{"answers":answers}}))
    }
    pub fn pages(&mut self, method: &str, mut params: Value) -> Result<Vec<Value>> {
        let mut all = Vec::new();
        let mut cursors = BTreeSet::new();
        loop {
            let reply = self.rpc_reply(method, params.clone())?;
            if method == "thread/turns/list"
                && params.get("cursor").is_none()
                && reply.get("result").is_none()
                && reply["error"]["code"] == -32600
            {
                let id = string(&params["threadId"])?;
                if reply["error"]["message"]
                    == format!(
                        "thread {id} is not materialized yet; thread/turns/list is unavailable before first user message"
                    )
                    && self.roots.contains_key(id)
                    && !self.submitted_turns.contains(id)
                {
                    let thread = self.require_loaded(id)?;
                    if thread["status"]["type"] == "idle"
                        && thread["ephemeral"] == false
                        && self.turns.keys().all(|(thread_id, _)| thread_id != id)
                    {
                        return Ok(all);
                    }
                }
            }
            let page = rpc_result(method, reply)?;
            all.extend(array(&page["data"])?.iter().cloned());
            match page.get("nextCursor") {
                Some(Value::Null) => return Ok(all),
                Some(Value::String(cursor))
                    if !cursor.is_empty() && cursors.insert(cursor.clone()) =>
                {
                    params["cursor"] = cursor.clone().into()
                }
                _ => return Err(format!("invalid {method} pagination").into()),
            }
        }
    }
    pub fn require_loaded(&mut self, root: &str) -> Result<Value> {
        ensure(
            self.pages("thread/loaded/list", json!({}))?
                .contains(&json!(root)),
            "loaded task root lost; cold resume/fork would reset its budget",
        )?;
        let thread = self.read_thread(root)?;
        let expected = self.roots.get(root).ok_or("untracked native budget root")?;
        ensure(
            ["sessionId", "model", "reasoningEffort", "cwd"]
                .iter()
                .all(|key| thread[key] == expected[key]),
            "loaded task root identity or model/effort changed; budget continuity is unknown",
        )?;
        Ok(thread)
    }
    fn list_threads(&mut self, mut filter: Value, archived: bool) -> Result<Vec<Value>> {
        filter["archived"] = json!(archived);
        filter["modelProviders"] = json!([]);
        filter["sourceKinds"] = json!([
            "cli",
            "vscode",
            "exec",
            "appServer",
            "subAgent",
            "subAgentReview",
            "subAgentCompact",
            "subAgentThreadSpawn",
            "subAgentOther",
            "unknown"
        ]);
        self.pages("thread/list", filter)
    }
    fn family(&mut self, root: &str) -> Result<BTreeSet<String>> {
        let mut ids = BTreeSet::from([root.into()]);
        for archived in [false, true] {
            let threads = self.list_threads(json!({"ancestorThreadId":root}), archived)?;
            for thread in threads {
                ensure(
                    ids.insert(string(&thread["id"])?.into()),
                    "conflicting native family listings",
                )?;
            }
        }
        Ok(ids)
    }
    fn confirmed_closed(&self, root: &str, id: &str) -> bool {
        self.unloaded.get(id) == Some(&true)
            && self
                .frozen_members
                .get(id)
                .is_some_and(|(owner, state)| owner == root && *state == FreezeState::Confirmed)
    }
    /// Freeze every writer before candidate capture; interrupt responses alone are not proof.
    pub fn freeze(&mut self, root: &str) -> Result<Vec<String>> {
        self.require_loaded(root)?;
        let session_id = self.roots[root]["sessionId"].clone();
        let mut previous = BTreeSet::new();
        loop {
            let family = self.family(root)?;
            ensure(
                previous.is_subset(&family),
                "a descendant disappeared before freeze was confirmed",
            )?;
            let loaded = self.pages("thread/loaded/list", json!({}))?;
            for id in &family {
                let is_loaded = loaded.contains(&json!(id));
                if !is_loaded || self.unloaded.contains_key(id) {
                    ensure(
                        !is_loaded && self.confirmed_closed(root, id),
                        "a descendant unloaded before its freeze was confirmed",
                    )?;
                    continue;
                }
                let thread = self.read_thread(id)?;
                ensure(
                    thread["sessionId"] == session_id,
                    format!("native thread {id} is outside the registered session"),
                )?;
                let (owner, state) = self
                    .frozen_members
                    .entry(id.clone())
                    .or_insert_with(|| (root.to_owned(), FreezeState::Unverified));
                ensure(
                    owner.as_str() == root,
                    "native thread changed its freeze owner",
                )?;
                *state = FreezeState::Unverified;
                let turns = self.pages("thread/turns/list", json!({"threadId":id}))?;
                let active: Vec<_> = turns
                    .iter()
                    .filter(|t| t["status"] == "inProgress")
                    .map(|t| string(&t["id"]).map(str::to_owned))
                    .collect::<Result<_>>()?;
                ensure(
                    thread["status"]["type"] != "active" || !active.is_empty(),
                    "active native thread has no identifiable turn",
                )?;
                ensure(
                    member(&thread["status"]["type"], &["idle", "active"]),
                    "native thread state cannot prove quiescence",
                )?;
                for turn in active {
                    self.rpc("turn/interrupt", json!({"threadId":id,"turnId":turn}))?;
                    loop {
                        let turns = self.pages("thread/turns/list", json!({"threadId":id}))?;
                        let status = turns
                            .iter()
                            .find(|t| t["id"] == turn)
                            .ok_or("interrupted turn disappeared")?["status"]
                            .clone();
                        if member(&status, &["completed", "interrupted", "failed"]) {
                            break;
                        }
                        ensure(status == "inProgress", "unknown interrupted turn result")?;
                        match self.rx.recv()? {
                            Input::Native(v) => self.observe(v)?,
                            Input::Command(v) => self.commands.push_back(v),
                            Input::Lost(reason) => return Err(reason.into()),
                        }
                    }
                }
                let terminals =
                    self.pages("thread/backgroundTerminals/list", json!({"threadId":id}))?;
                for terminal in terminals {
                    let terminated = self.rpc(
                        "thread/backgroundTerminals/terminate",
                        json!({"threadId":id,"processId":terminal["processId"]}),
                    )?;
                    ensure(
                        terminated["terminated"] == true,
                        "background terminal termination was not confirmed; freeze is unknown",
                    )?;
                }
                self.frozen_members.get_mut(id).unwrap().1 = FreezeState::Pending;
                ensure(
                    self.pages("thread/backgroundTerminals/list", json!({"threadId":id}))?
                        .is_empty(),
                    "background terminals remain; freeze is unknown",
                )?;
                let turns = self.pages("thread/turns/list", json!({"threadId":id}))?;
                let thread = self.read_thread(id)?;
                ensure(
                    thread["status"]["type"] == "idle"
                        && turns
                            .iter()
                            .all(|t| member(&t["status"], &["completed", "interrupted", "failed"])),
                    "new native activity prevents capture",
                )?;
            }
            self.require_loaded(root)?;
            let after = self.family(root)?;
            ensure(
                family.is_subset(&after),
                "a descendant disappeared before freeze was confirmed",
            )?;
            ensure(
                family
                    .iter()
                    .all(|id| !self.unloaded.contains_key(id) || self.confirmed_closed(root, id)),
                "a descendant unloaded before its freeze was confirmed",
            )?;
            ensure(
                family
                    .iter()
                    .all(|id| self.frozen_members[id].1 != FreezeState::Unverified),
                "new native activity prevents capture",
            )?;
            if family == after && family == previous {
                for id in &family {
                    self.frozen_members.get_mut(id).unwrap().1 = FreezeState::Confirmed;
                }
                return Ok(family.into_iter().collect());
            }
            previous = family;
        }
    }
    fn read_thread(&mut self, id: &str) -> Result<Value> {
        let mut reply = self.rpc("thread/read", json!({"threadId":id}))?;
        ensure(
            reply["thread"]["id"] == id,
            format!("native read returned a different thread for {id}"),
        )?;
        Ok(reply["thread"].take())
    }
    pub fn close_snapshot(&mut self) -> Result<BTreeMap<String, FrozenThread>> {
        // The history lists can miss loaded threads that have not materialized yet.
        let mut live = BTreeMap::new();
        for value in self.pages("thread/loaded/list", json!({}))? {
            let id = string(&value)?;
            ensure(
                live.insert(id.to_owned(), self.read_thread(id)?).is_none(),
                "duplicate loaded thread ID",
            )?;
        }
        let mut snapshot = BTreeMap::new();
        for (root, expected) in self.roots.clone() {
            let session_id = string(&expected["sessionId"])?;
            let mut family = self.family(&root)?;
            family.extend(
                live.iter()
                    .filter(|(_, thread)| thread["sessionId"] == session_id)
                    .map(|(id, _)| id.clone()),
            );
            loop {
                let extra: Vec<_> = live
                    .iter()
                    .filter(|(id, thread)| {
                        !family.contains(*id)
                            && thread["parentThreadId"]
                                .as_str()
                                .is_some_and(|parent| family.contains(parent))
                    })
                    .map(|(id, _)| id.clone())
                    .collect();
                if extra.is_empty() {
                    break;
                }
                family.extend(extra);
            }
            for id in &family {
                let loaded = live.contains_key(id);
                let thread = match live.get(id) {
                    Some(thread) => thread.clone(),
                    None => self.read_thread(id)?,
                };
                let parent = thread
                    .get("parentThreadId")
                    .ok_or("native parent identity is missing")?;
                ensure(
                    thread["ephemeral"] == false
                        && if id == &root {
                            parent.is_null() && thread["cwd"] == expected["cwd"]
                        } else {
                            parent.as_str().is_some_and(|p| family.contains(p))
                        },
                    format!("unverified task ownership for native thread {id}"),
                )?;
                ensure(
                    if loaded {
                        thread["sessionId"] == session_id && thread["status"]["type"] == "idle"
                    } else {
                        // The stored view substitutes the thread ID for sessionId.
                        // Its parent chain must still reach the registered root.
                        (self.confirmed_closed(&root, id) || self.archive_members.contains(id))
                            && thread["sessionId"] == id.as_str()
                            && thread["status"]["type"] == "notLoaded"
                    },
                    format!("unverified session or activity for native thread {id}"),
                )?;
                let mut turns = BTreeMap::new();
                for turn in self.pages("thread/turns/list", json!({"threadId":id}))? {
                    ensure(
                        member(&turn["status"], &["completed", "interrupted", "failed"]),
                        format!("native thread {id} has an active or unknown turn"),
                    )?;
                    ensure(
                        turns
                            .insert(
                                string(&turn["id"])?.to_owned(),
                                string(&turn["status"])?.to_owned(),
                            )
                            .is_none(),
                        "duplicate native turn ID",
                    )?;
                }
                ensure(
                    !loaded
                        || self
                            .pages("thread/backgroundTerminals/list", json!({"threadId":id}))?
                            .is_empty(),
                    format!("native thread {id} still has background terminals"),
                )?;
                ensure(
                    !loaded || self.archive_deadline.is_some() || !self.unloaded.contains_key(id),
                    format!("native thread {id} unloaded before close freeze was confirmed"),
                )?;
                let facts = FrozenThread {
                    root: root.clone(),
                    parent_thread_id: parent.as_str().map(str::to_owned),
                    session_id: session_id.into(),
                    cwd: string(&thread["cwd"])?.into(),
                    turns,
                    loaded,
                };
                ensure(
                    snapshot.insert(id.clone(), facts).is_none(),
                    "native thread belongs to multiple task roots",
                )?;
            }
            for id in &family {
                ensure(
                    lineage(&snapshot, id).take(family.len()).last() == Some(root.as_str()),
                    format!("native parent chain for {id} does not reach {root}"),
                )?;
            }
        }
        ensure(
            self.frozen_members
                .keys()
                .all(|id| snapshot.contains_key(id)),
            "a previously frozen thread is missing at close",
        )?;
        for (id, facts) in &snapshot {
            let (_, state) = self
                .frozen_members
                .get(id)
                .filter(|(owner, _)| owner == &facts.root)
                .ok_or_else(|| format!("native thread {id} has no freeze under its root"))?;
            ensure(
                *state == FreezeState::Confirmed,
                format!("native activity invalidated close freeze for {id}"),
            )?;
        }
        Ok(snapshot)
    }
    fn archive_inventory(
        &mut self,
        frozen: &BTreeMap<String, FrozenThread>,
        states: &mut BTreeMap<String, &'static str>,
        unlisted: &mut BTreeSet<String>,
    ) -> Result<()> {
        let mut found = BTreeMap::new();
        let cwds: BTreeSet<_> = self
            .roots
            .values()
            .map(|root| string(&root["cwd"]).map(str::to_owned))
            .collect::<Result<_>>()?;
        let roots: Vec<_> = self.roots.keys().cloned().collect();
        for archived in [false, true] {
            let state = if archived { "archived" } else { "unarchived" };
            let mut add = |id: &str| -> Result<()> {
                if found.insert(id.to_owned(), state).is_some() {
                    states.insert(id.to_owned(), "unknown");
                    return Err(format!("conflicting archive listings for {id}").into());
                }
                Ok(())
            };
            for thread in self.list_threads(json!({"cwd":cwds}), archived)? {
                let id = string(&thread["id"])?;
                if self.roots.contains_key(id) {
                    add(id)?;
                }
            }
            for root in &roots {
                for thread in self.list_threads(json!({"ancestorThreadId":root}), archived)? {
                    let id = string(&thread["id"])?;
                    ensure(
                        frozen
                            .get(id)
                            .is_some_and(|f| &f.root == root && id != root.as_str()),
                        format!("native archive family changed for {root}: {id}"),
                    )?;
                    add(id)?;
                }
            }
        }
        for id in frozen.keys() {
            match found.get(id) {
                Some(&"archived") => {}
                Some(&"unarchived") if states[id] != "archived" => {}
                None if unlisted.contains(id) => {}
                _ => {
                    states.insert(id.clone(), "unknown");
                    return Err(format!("missing or conflicting archive state for {id}").into());
                }
            }
        }
        remaining(self.archive_deadline.unwrap())?;
        unlisted.retain(|id| !found.contains_key(id));
        states.extend(found);
        Ok(())
    }
    pub fn archive(
        &mut self,
        frozen: &BTreeMap<String, FrozenThread>,
        states: &mut BTreeMap<String, &'static str>,
    ) -> Result<()> {
        self.archive_deadline = Some(Instant::now() + Duration::from_secs(30));
        self.archive_members = frozen.keys().cloned().collect();
        let stdin = self.stdin.as_ref().ok_or("native connection is closed")?;
        let flags = OFlag::from_bits_truncate(fcntl(stdin, FcntlArg::F_GETFL)?);
        fcntl(stdin, FcntlArg::F_SETFL(flags | OFlag::O_NONBLOCK))?;

        // A fresh persistent thread is absent until its first turn or explicit archive.
        let mut unlisted: BTreeSet<_> = frozen
            .iter()
            .filter(|(_, f)| f.loaded && f.turns.is_empty())
            .map(|(id, _)| id.clone())
            .collect();
        self.archive_inventory(frozen, states, &mut unlisted)?;
        let mut rejection = None;
        for round in 0..2 {
            if round == 1 {
                let current = self.close_snapshot()?;
                ensure(
                    current.len() == frozen.len()
                        && current.iter().all(|(id, now)| {
                            frozen.get(id).is_some_and(|was| {
                                now.root == was.root
                                    && now.parent_thread_id == was.parent_thread_id
                                    && now.session_id == was.session_id
                                    && now.cwd == was.cwd
                                    && now.turns == was.turns
                                    && (!now.loaded || was.loaded)
                            })
                        }),
                    "native ownership or freeze changed before archive retry",
                )?;
                self.archive_inventory(frozen, states, &mut unlisted)?;
            }
            let mut pending: BTreeSet<_> = states
                .iter()
                .filter(|(_, state)| **state != "archived")
                .map(|(id, _)| id.clone())
                .collect();
            while let Some(id) = pending
                .iter()
                .min_by_key(|id| {
                    let depth = lineage(frozen, id).count();
                    // An ancestor can unload an unmaterialized child or fail to archive a remaining child.
                    if round == 1 || unlisted.contains(*id) {
                        (false, frozen.len() - depth)
                    } else {
                        (true, depth)
                    }
                })
                .cloned()
            {
                for (member, state) in states.iter_mut() {
                    if lineage(frozen, member).any(|p| p == id) {
                        pending.remove(member);
                        unlisted.remove(member);
                        if *state != "archived" {
                            *state = "unknown";
                        }
                    }
                }
                let reply = self.rpc_reply("thread/archive", json!({"threadId":id}))?;
                if let Some(error) = reply.get("error") {
                    ensure(
                        error["code"].is_i64()
                            && error["message"].is_string()
                            && reply.get("result").is_none(),
                        "malformed native archive error response",
                    )?;
                    rejection = Some(format!("native thread/archive for {id}: {error}"));
                } else {
                    ensure(
                        reply["result"].is_object(),
                        "malformed native archive response",
                    )?;
                }
                self.archive_inventory(frozen, states, &mut unlisted)?;
                pending.retain(|member| states[member] != "archived");
            }
            if states.values().all(|state| *state == "archived") {
                return Ok(());
            }
        }
        Err(rejection
            .unwrap_or_else(|| "native archive left unarchived threads".into())
            .into())
    }
    pub fn shutdown(mut self) -> Value {
        self.stdin.take();
        let mut exit = self.wait_child(Duration::from_secs(5));
        let mut killed = None;
        if matches!(exit, Ok(None)) {
            killed = Some(self.child.kill());
            exit = self.wait_child(Duration::from_millis(250));
        }
        // The launcher can exit while its App Server still holds stdout open.
        if matches!(exit, Ok(Some(_)))
            && (!self.stdout_reader.is_finished() || !matches!(self.stdout_reader.join(), Ok(true)))
        {
            return json!({"status":"unknown","error":"App Server stdout closure could not be confirmed"});
        }
        match exit {
            Ok(Some(status)) if status.success() => json!({"status":"exited"}),
            Ok(Some(status)) if matches!(killed, Some(Ok(()))) => {
                json!({"status":"terminated","exit":status.to_string()})
            }
            Ok(Some(status)) => json!({"status":"failed","error":status.to_string()}),
            Err(error) => json!({"status":"unknown","error":error.to_string()}),
            Ok(None) => json!({"status":"unknown","error":killed.and_then(|result| result.err())
                .map_or_else(|| "App Server exit could not be confirmed".into(), |error| error.to_string())}),
        }
    }
    fn wait_child(&mut self, window: Duration) -> io::Result<Option<ExitStatus>> {
        let deadline = Instant::now() + window;
        loop {
            let result = self.child.try_wait()?;
            let delay = deadline.saturating_duration_since(Instant::now());
            if delay.is_zero() || result.is_some() && self.stdout_reader.is_finished() {
                return Ok(result);
            }
            thread::sleep(delay.min(Duration::from_millis(10)));
        }
    }
}
fn rpc_result(method: &str, reply: Value) -> Result<Value> {
    ensure(
        reply.get("error").is_none(),
        format!("native {method}: {}", reply["error"]),
    )?;
    reply
        .get("result")
        .cloned()
        .ok_or_else(|| "native response lacks result".into())
}

fn lineage<'a>(
    frozen: &'a BTreeMap<String, FrozenThread>,
    id: &'a str,
) -> impl Iterator<Item = &'a str> {
    std::iter::successors(Some(id), |current| {
        frozen[*current].parent_thread_id.as_deref()
    })
}
fn remaining(deadline: Instant) -> Result<Duration> {
    deadline
        .checked_duration_since(Instant::now())
        .filter(|time| !time.is_zero())
        .ok_or_else(|| "native archive exceeded its 30-second deadline".into())
}
fn final_text(turn: &mut TurnResult, item: &Value) -> Result<()> {
    if item["type"] == "agentMessage"
        && (item["phase"].is_null() || item["phase"] == "final_answer")
    {
        let text = string(&item["text"])?;
        let mut end = text.len().min(FINAL_LIMIT);
        while !text.is_char_boundary(end) {
            end -= 1;
        }
        turn.text = text[..end].into();
        turn.text_error = (text.len() > FINAL_LIMIT)
            .then(|| "native final output exceeds 64 KiB report limit; rawReport truncated".into());
    }
    Ok(())
}
pub fn outcome(turn: &TurnResult, review: bool) -> Value {
    let parsed = strict_json(turn.text.as_bytes());
    let (report, report_error) = match parsed {
        Ok(report) => {
            let error = if review {
                validate_review(&report)
            } else {
                validate_executor(&report)
            }
            .err()
            .map(|e| e.to_string());
            (report, error)
        }
        Err(error) => (Value::Null, Some(error.to_string())),
    };
    let report_error = turn.text_error.clone().or(report_error);
    let status = if turn.completed {
        turn.status.as_str()
    } else {
        "unknown"
    };
    let result = if status != "completed" {
        match status {
            "failed" | "interrupted" if turn.error["codexErrorInfo"] == "sessionBudgetExceeded" => {
                "budget_exhausted"
            }
            // Codex 0.169.0 exposes these native timeouts as Other, without a typed timeout code.
            "failed" | "interrupted"
                if turn.error["codexErrorInfo"] == "other"
                    && member(
                        &turn.error["message"],
                        &[
                            "request timed out",
                            "timeout waiting for child process to exit",
                        ],
                    ) =>
            {
                "timed_out"
            }
            "interrupted" => "cancelled",
            "failed" => "failed",
            _ => "unknown",
        }
    } else if !turn.error.is_null() || report_error.is_some() {
        "invalid_output"
    } else {
        report[if review { "verdict" } else { "status" }]
            .as_str()
            .unwrap()
    };
    json!({"outcome":result,"nativeStatus":status,"lastNativeStatus":turn.status,
        "rawReport":turn.text,"report":report,"reportError":report_error,"nativeError":turn.error,
        "finalUsage":if status == "completed" && turn.error.is_null() { &turn.usage } else { &Value::Null }})
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn native_results_require_terminal_valid_output() {
        let report = json!({"verdict":"APPROVE","summary":"checked","findings":[],"coverage":[{"check":"scope","status":"PASS","evidence":"read"}],"review_blockers":[],"deferred_acceptance":[]});
        let mut turn = TurnResult {
            status: "completed".into(),
            completed: true,
            text: report.to_string(),
            usage: json!({"total":{"totalTokens":12}}),
            ..Default::default()
        };
        assert_eq!(outcome(&turn, true)["outcome"], "APPROVE");
        assert_eq!(outcome(&turn, true)["finalUsage"], turn.usage);
        for (status, expected) in [
            ("interrupted", "cancelled"),
            ("failed", "failed"),
            ("inProgress", "unknown"),
            ("unknown", "unknown"),
        ] {
            turn.status = status.into();
            let saved = outcome(&turn, true);
            assert_eq!(saved["outcome"], expected);
            assert_eq!(saved["report"], report);
            assert_eq!(saved["rawReport"], turn.text);
            assert!(saved["finalUsage"].is_null());
        }
        for (error, expected) in [
            (
                json!({"codexErrorInfo":"sessionBudgetExceeded","message":"budget reached"}),
                "budget_exhausted",
            ),
            (
                json!({"codexErrorInfo":"other","message":"request timed out"}),
                "timed_out",
            ),
            (
                json!({"codexErrorInfo":"other","message":"timeout waiting for child process to exit"}),
                "timed_out",
            ),
            (
                json!({"codexErrorInfo":"other","message":"unknown timeout-like error"}),
                "failed",
            ),
        ] {
            turn.status = "failed".into();
            turn.error = error;
            let saved = outcome(&turn, true);
            assert_eq!(saved["outcome"], expected);
            assert_eq!(saved["report"], report);
            assert_eq!(saved["nativeError"], turn.error);
        }
        turn.status = "completed".into();
        assert_eq!(outcome(&turn, true)["outcome"], "invalid_output");
        turn.error = Value::Null;
        turn.completed = false;
        assert_eq!(outcome(&turn, true)["nativeStatus"], "unknown");
        assert_eq!(outcome(&turn, true)["report"], report);
        turn.completed = true;
        turn.text = "no findings".into();
        assert_eq!(outcome(&turn, true)["outcome"], "invalid_output");
        assert!(outcome(&turn, true)["reportError"].is_string());
        turn.text = json!({"verdict":"APPROVE","summary":"incomplete"}).to_string();
        assert_eq!(outcome(&turn, true)["report"]["summary"], "incomplete");
        assert!(outcome(&turn, true)["reportError"].is_string());
        turn.text.clear();
        turn.status = "failed".into();
        assert_eq!(outcome(&turn, true)["outcome"], "failed");
        assert!(outcome(&turn, true)["report"].is_null());
    }
    #[test]
    fn report_limit_retains_a_bounded_utf8_diagnostic() {
        let mut turn = TurnResult::default();
        final_text(
            &mut turn,
            &json!({"type":"agentMessage","text":"中".repeat(FINAL_LIMIT)}),
        )
        .unwrap();
        assert!(turn.text.len() <= FINAL_LIMIT);
        let saved = outcome(&turn, true);
        assert!(saved["reportError"].as_str().unwrap().contains("64 KiB"));
        assert_eq!(saved["rawReport"], turn.text);
        final_text(&mut turn, &json!({"type":"agentMessage","text":"{}"})).unwrap();
        assert!(turn.text_error.is_none());
    }
}

use crate::{Result, contracts::*, ensure};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet, VecDeque},
    io::{BufRead, BufReader, Write},
    path::Path,
    process::{Child, ChildStdin, Command, Stdio},
    sync::mpsc::{self, Receiver, Sender},
    thread,
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
fn lines(reader: impl std::io::Read + Send + 'static, tx: Sender<Input>, controller: bool) {
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
                return;
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
    });
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
/// A connected official App Server, with only the native facts needed for acceptance.
pub struct Native {
    child: Child,
    stdin: Option<ChildStdin>,
    rx: Receiver<Input>,
    commands: VecDeque<Value>,
    next_id: u64,
    pub pending_turn: Option<(String, String)>,
    pub turns: BTreeMap<(String, String), TurnResult>,
    pub usage: BTreeMap<String, Value>,
    closed: BTreeSet<String>,
    questions: BTreeSet<String>,
    pub roots: BTreeMap<String, Value>,
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
        lines(
            child.stdout.take().ok_or("missing native stdout")?,
            tx.clone(),
            false,
        );
        if controller {
            lines(std::io::stdin(), tx, true);
        }
        let mut client = Self {
            child,
            stdin,
            rx,
            commands: VecDeque::new(),
            next_id: 0,
            pending_turn: None,
            turns: BTreeMap::new(),
            usage: BTreeMap::new(),
            closed: BTreeSet::new(),
            questions: BTreeSet::new(),
            roots: BTreeMap::new(),
        };
        client.rpc("initialize",json!({"clientInfo":{"name":"codex_improve","version":"0.20.0"},"capabilities":{"experimentalApi":true}}))?;
        client.send(&json!({"method":"initialized"}))?;
        Ok(client)
    }
    fn send(&mut self, v: &Value) -> Result<()> {
        let stdin = self.stdin.as_mut().ok_or("native connection is closed")?;
        serde_json::to_writer(&mut *stdin, v)?;
        writeln!(stdin)?;
        stdin.flush()?;
        Ok(())
    }
    pub fn rpc(&mut self, method: &str, params: Value) -> Result<Value> {
        if method == "turn/start" {
            self.pending_turn = None;
        }
        self.next_id += 1;
        let id = self.next_id;
        self.send(&json!({"id":id,"method":method,"params":params}))?;
        loop {
            match self.rx.recv()? {
                Input::Lost(reason) => return Err(reason.into()),
                Input::Command(v) => self.commands.push_back(v),
                Input::Native(v) => {
                    if v.get("method").is_none() && v["id"] == id {
                        ensure(
                            v.get("error").is_none(),
                            format!("native {method}: {}", v["error"]),
                        )?;
                        let result = v
                            .get("result")
                            .cloned()
                            .ok_or("native response lacks result")?;
                        if method == "turn/start" {
                            self.pending_turn = None;
                        }
                        return Ok(result);
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
        match method {
            "model/rerouted" => {
                return Err("native model changed; no fallback is authorized".into());
            }
            "thread/closed" => {
                self.closed.insert(string(&p["threadId"])?.into());
            }
            "thread/status/changed" if p["status"]["type"] == "notLoaded" => {
                ensure(
                    !self.roots.contains_key(string(&p["threadId"])?),
                    "loaded task root lost; a new budget root requires authorization",
                )?;
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
        ensure(
            self.roots.keys().all(|root| !self.closed.contains(root)),
            "loaded task root lost; a new budget root requires authorization",
        )?;
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
            let page = self.rpc(method, params.clone())?;
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
    pub fn require_loaded(&mut self, root: &str) -> Result<()> {
        ensure(
            self.pages("thread/loaded/list", json!({}))?
                .contains(&json!(root)),
            "loaded task root lost; cold resume/fork would reset its budget",
        )?;
        let read = self.rpc("thread/read", json!({"threadId":root}))?;
        let expected = self.roots.get(root).ok_or("untracked native budget root")?;
        ensure(
            ["sessionId", "model", "reasoningEffort", "cwd"]
                .iter()
                .all(|key| read["thread"][key] == expected[key]),
            "loaded task root identity or model/effort changed; budget continuity is unknown",
        )
    }
    fn family(&mut self, root: &str) -> Result<BTreeSet<String>> {
        let mut ids = BTreeSet::from([root.into()]);
        for archived in [false, true] {
            let threads=self.pages("thread/list",json!({"ancestorThreadId":root,"archived":archived,"modelProviders":[],"sourceKinds":["cli","vscode","exec","appServer","subAgent","subAgentReview","subAgentCompact","subAgentThreadSpawn","subAgentOther","unknown"]}))?;
            for thread in threads {
                ids.insert(string(&thread["id"])?.into());
            }
        }
        Ok(ids)
    }
    /// Freeze every writer before candidate capture; interrupt responses alone are not proof.
    pub fn freeze(&mut self, root: &str) -> Result<Vec<String>> {
        self.require_loaded(root)?;
        let mut previous = BTreeSet::new();
        loop {
            let family = self.family(root)?;
            let loaded = self.pages("thread/loaded/list", json!({}))?;
            for id in &family {
                if !loaded.contains(&json!(id)) {
                    ensure(
                        self.closed.contains(id),
                        "descendant disappeared without confirmed native closure; freeze is unknown",
                    )?;
                    continue;
                }
                let read = self.rpc("thread/read", json!({"threadId":id}))?;
                let turns = self.pages("thread/turns/list", json!({"threadId":id}))?;
                let active: Vec<_> = turns
                    .iter()
                    .filter(|t| t["status"] == "inProgress")
                    .map(|t| string(&t["id"]).map(str::to_owned))
                    .collect::<Result<_>>()?;
                ensure(
                    read["thread"]["status"]["type"] != "active" || !active.is_empty(),
                    "active native thread has no identifiable turn",
                )?;
                ensure(
                    member(&read["thread"]["status"]["type"], &["idle", "active"]),
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
                ensure(
                    self.pages("thread/backgroundTerminals/list", json!({"threadId":id}))?
                        .is_empty(),
                    "background terminals remain; freeze is unknown",
                )?;
                let turns = self.pages("thread/turns/list", json!({"threadId":id}))?;
                let read = self.rpc("thread/read", json!({"threadId":id}))?;
                ensure(
                    read["thread"]["status"]["type"] == "idle"
                        && turns
                            .iter()
                            .all(|t| member(&t["status"], &["completed", "interrupted", "failed"])),
                    "new native activity prevents capture",
                )?;
            }
            self.require_loaded(root)?;
            let after = self.family(root)?;
            if family == after && family == previous {
                return Ok(family.into_iter().collect());
            }
            previous = family;
        }
    }
    pub fn shutdown(mut self) -> Result<()> {
        self.stdin.take();
        ensure(self.child.wait()?.success(), "App Server shutdown failed")
    }
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

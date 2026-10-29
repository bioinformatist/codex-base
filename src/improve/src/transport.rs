use crate::{
    Result,
    contracts::*,
    ensure,
    state::{atomic_private, private_read},
};
use nix::{
    libc,
    sys::signal::{Signal, killpg},
    unistd::Pid,
};
use serde_json::{Value, json};
use std::{
    collections::BTreeMap,
    fs::File,
    io::{Read, Seek, SeekFrom, Write},
    os::{
        fd::AsRawFd,
        unix::process::{CommandExt, ExitStatusExt},
    },
    path::{Path, PathBuf},
    process::{Command, Stdio},
    sync::atomic::{AtomicBool, Ordering},
    time::{Duration, Instant},
};

static CANCELLED: AtomicBool = AtomicBool::new(false);
extern "C" fn cancel(_: libc::c_int) {
    CANCELLED.store(true, Ordering::Relaxed);
}
struct Handlers(Vec<(i32, libc::sigaction)>);
impl Handlers {
    fn install() -> Result<Self> {
        CANCELLED.store(false, Ordering::Relaxed);
        let mut handlers = Self(Vec::new());
        for signal in [libc::SIGINT, libc::SIGTERM] {
            unsafe {
                let mut action: libc::sigaction = std::mem::zeroed();
                action.sa_sigaction = cancel as *const () as usize;
                libc::sigemptyset(&mut action.sa_mask);
                let mut old = std::mem::zeroed();
                if libc::sigaction(signal, &action, &mut old) != 0 {
                    return Err(std::io::Error::last_os_error().into());
                }
                handlers.0.push((signal, old));
            }
        }
        Ok(handlers)
    }
}
impl Drop for Handlers {
    fn drop(&mut self) {
        for (signal, old) in &self.0 {
            unsafe {
                libc::sigaction(*signal, old, std::ptr::null_mut());
            }
        }
    }
}
#[derive(Debug)]
pub struct ProcessResult {
    pub status: i32,
    pub reason: String,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub elapsed: f64,
    pub quiet_observed: bool,
    pub stdout_truncated: bool,
}
pub struct ProcessOptions<'a> {
    pub cwd: &'a Path,
    pub env: &'a BTreeMap<String, String>,
    pub stdin: &'a [u8],
    pub deadline: f64,
    pub stdout_limit: usize,
    pub stderr_limit: usize,
    pub group_file: Option<&'a Path>,
    pub inner_group: Option<&'a Path>,
    pub stdout_sink: Option<File>,
    pub stderr_sink: Option<File>,
}
impl<'a> ProcessOptions<'a> {
    pub fn new(cwd: &'a Path, env: &'a BTreeMap<String, String>, deadline: f64) -> Self {
        Self {
            cwd,
            env,
            stdin: b"",
            deadline,
            stdout_limit: 32 * 1024 * 1024,
            stderr_limit: 1024 * 1024,
            group_file: None,
            inner_group: None,
            stdout_sink: None,
            stderr_sink: None,
        }
    }
}
fn stop_inner(path: Option<&Path>, signal: Signal) {
    if let Some(path) = path {
        if let Ok(raw) = private_read(path) {
            if let Ok(pid) = String::from_utf8_lossy(&raw).parse::<i32>() {
                if pid > 1 {
                    let _ = killpg(Pid::from_raw(pid), signal);
                }
            }
        }
    }
}
pub fn run_process(argv: &[String], mut options: ProcessOptions<'_>) -> Result<ProcessResult> {
    let _handlers = Handlers::install()?;
    let started = Instant::now();
    let mut input = tempfile::tempfile()?;
    input.write_all(options.stdin)?;
    input.seek(SeekFrom::Start(0))?;
    let mut cmd = Command::new(&argv[0]);
    cmd.args(&argv[1..])
        .current_dir(options.cwd)
        .envs(options.env)
        .stdin(input)
        .stdout(Stdio::piped())
        .stderr(Stdio::piped());
    unsafe {
        cmd.pre_exec(|| {
            if libc::setsid() == -1 {
                return Err(std::io::Error::last_os_error());
            }
            Ok(())
        });
    }
    let mut child = cmd.spawn().map_err(|e| {
        format!(
            "missing required command or failed to start {}: {e}",
            argv[0]
        )
    })?;
    let pgid = Pid::from_raw(child.id() as i32);
    let stop = |signal| {
        let _ = killpg(pgid, signal);
        stop_inner(options.inner_group, signal);
    };
    if let Some(path) = options.group_file {
        if let Err(e) = atomic_private(path, child.id().to_string().as_bytes()) {
            stop(Signal::SIGKILL);
            let _ = child.wait();
            return Err(e);
        }
    }
    let mut stdout = child.stdout.take().ok_or("stdout pipe missing")?;
    let mut stderr = child.stderr.take().ok_or("stderr pipe missing")?;
    let fds = [stdout.as_raw_fd(), stderr.as_raw_fd()];
    let mut open = [true, true];
    let mut output = [Vec::new(), Vec::new()];
    let mut reason = "exit";
    let mut terminating = None;
    let mut last_content = Instant::now();
    let mut heartbeat = Instant::now();
    let mut quiet = false;
    let mut truncated = false;
    let result: Result<i32> = (|| {
        for fd in fds {
            if unsafe { libc::fcntl(fd, libc::F_SETFL, libc::O_NONBLOCK) } == -1 {
                return Err(std::io::Error::last_os_error().into());
            }
        }
        loop {
            if terminating.is_none() {
                if CANCELLED.load(Ordering::Relaxed) {
                    reason = "caller_signal";
                    terminating = Some(Instant::now());
                    stop(Signal::SIGINT);
                } else if started.elapsed().as_secs_f64() >= options.deadline {
                    reason = "absolute_timeout";
                    terminating = Some(Instant::now());
                    stop(Signal::SIGINT);
                }
            } else if terminating.unwrap().elapsed() >= Duration::from_secs(5) {
                stop(Signal::SIGKILL);
            }
            quiet |= last_content.elapsed() >= Duration::from_secs(180);
            if heartbeat.elapsed() >= Duration::from_secs(60) {
                eprintln!("codex-improve: process active; no content logged");
                heartbeat = Instant::now();
            }
            let mut polls = [
                libc::pollfd {
                    fd: if open[0] { fds[0] } else { -1 },
                    events: libc::POLLIN,
                    revents: 0,
                },
                libc::pollfd {
                    fd: if open[1] { fds[1] } else { -1 },
                    events: libc::POLLIN,
                    revents: 0,
                },
            ];
            let polled = unsafe { libc::poll(polls.as_mut_ptr(), 2, 200) };
            if polled < 0
                && std::io::Error::last_os_error().kind() != std::io::ErrorKind::Interrupted
            {
                return Err(std::io::Error::last_os_error().into());
            }
            for i in 0..2 {
                if polls[i].revents == 0 {
                    continue;
                }
                let mut chunk = [0; 65536];
                let n = match if i == 0 {
                    stdout.read(&mut chunk)
                } else {
                    stderr.read(&mut chunk)
                } {
                    Ok(n) => n,
                    Err(e)
                        if [
                            std::io::ErrorKind::WouldBlock,
                            std::io::ErrorKind::Interrupted,
                        ]
                        .contains(&e.kind()) =>
                    {
                        continue;
                    }
                    Err(e) => return Err(e.into()),
                };
                if n == 0 {
                    open[i] = false;
                    continue;
                }
                last_content = Instant::now();
                let limit = if i == 0 {
                    options.stdout_limit
                } else {
                    options.stderr_limit
                };
                let accepted = n.min(limit.saturating_sub(output[i].len()));
                output[i].extend_from_slice(&chunk[..accepted]);
                if let Some(sink) = if i == 0 {
                    options.stdout_sink.as_mut()
                } else {
                    options.stderr_sink.as_mut()
                } {
                    sink.write_all(&chunk[..accepted])?;
                }
                if i == 0 && accepted < n {
                    truncated = true;
                    if terminating.is_none() {
                        reason = "event_log_limit";
                        terminating = Some(Instant::now());
                        stop(Signal::SIGINT);
                    }
                }
            }
            if !open[0] && !open[1] {
                if let Some(status) = child.try_wait()? {
                    return Ok(status
                        .code()
                        .unwrap_or_else(|| -status.signal().unwrap_or(1)));
                }
            }
        }
    })();
    if result.is_err() || terminating.is_some() {
        stop(Signal::SIGKILL);
    }
    let _ = child.wait();
    Ok(ProcessResult {
        status: result?,
        reason: reason.into(),
        stdout: std::mem::take(&mut output[0]),
        stderr: std::mem::take(&mut output[1]),
        elapsed: started.elapsed().as_secs_f64(),
        quiet_observed: quiet,
        stdout_truncated: truncated,
    })
}
pub fn parse_events(raw: &[u8]) -> Result<(Vec<Value>, Value)> {
    let mut events = Vec::new();
    let mut metrics = json!({"usage_observed":false,"token_usage":null,"tool_events":0,"command_executions":0,"file_changes":0,"mcp_tool_calls":0,"web_searches":0});
    for line in raw
        .strip_suffix(b"\n")
        .unwrap_or(raw)
        .split(|b| *b == b'\n')
    {
        let event = strict_json(line)?;
        ensure(
            event.is_object() && event["type"].is_string(),
            "invalid native JSONL event",
        )?;
        if event["type"] == "turn.completed"
            && ["input_tokens", "cached_input_tokens", "output_tokens"]
                .iter()
                .all(|k| integer(&event["usage"][k], 0, u64::MAX))
        {
            metrics["usage_observed"] = true.into();
            metrics["token_usage"] = json!({"input_tokens":event["usage"]["input_tokens"],"cached_input_tokens":event["usage"]["cached_input_tokens"],"output_tokens":event["usage"]["output_tokens"]});
        }
        if string(&event["type"])?.starts_with("item.") {
            for (key, kind) in [
                ("tool_events", None),
                ("command_executions", Some("command_execution")),
                ("file_changes", Some("file_change")),
                ("mcp_tool_calls", Some("mcp_tool_call")),
                ("web_searches", Some("web_search")),
            ] {
                if kind.is_none() || event["item"]["type"].as_str() == kind {
                    metrics[key] = (metrics[key].as_u64().unwrap() + 1).into();
                }
            }
        }
        events.push(event);
    }
    ensure(!events.is_empty(), "empty native JSONL stream")?;
    Ok((events, metrics))
}
pub fn classify(
    process: &ProcessResult,
    raw: &[u8],
    kind: &str,
    images: &[Value],
) -> (String, String, Value, Value) {
    let parsed = parse_events(&process.stdout);
    let valid = parsed.is_ok();
    let (events, mut metrics) = parsed.unwrap_or_else(|_| {
        (
            Vec::new(),
            json!({"usage_observed":false,"token_usage":null}),
        )
    });
    metrics["exit_status"] = process.status.into();
    metrics["elapsed_seconds"] = json!((process.elapsed * 1000.0).round() / 1000.0);
    metrics["quiet_observed"] = process.quiet_observed.into();
    metrics["event_evidence_valid"] = (valid && !process.stdout_truncated).into();
    metrics["event_log_truncated"] = process.stdout_truncated.into();
    let failure = if process.reason != "exit" {
        Some(process.reason.clone())
    } else if process.status != 0 {
        Some(
            if events.iter().any(|e| {
                e["type"] == "error" && e["message"] == "shared rollout token budget exhausted"
            }) {
                "rollout_budget_exhausted".into()
            } else {
                format!("codex_exit_{}", process.status)
            },
        )
    } else if !valid || !events.iter().any(|e| e["type"] == "turn.completed") {
        Some("invalid_event_log".into())
    } else if raw.is_empty() {
        Some("empty_final_output".into())
    } else if raw.len() > FINAL_LIMIT {
        Some("final_output_limit".into())
    } else {
        None
    };
    if let Some(reason) = failure {
        return ("INCONCLUSIVE".into(), reason, Value::Null, metrics);
    }
    let report: Result<Value> = (|| {
        let v = strict_json(raw)?;
        match kind {
            "review" => validate_review(&v)?,
            "visual" => crate::visual::validate_visual(&v, images)?,
            _ => validate_executor(&v)?,
        };
        Ok(v)
    })();
    match report {
        Ok(v) => (
            v[if kind == "review" {
                "verdict"
            } else {
                "status"
            }]
            .as_str()
            .unwrap()
            .into(),
            "completed".into(),
            v,
            metrics,
        ),
        Err(e) => {
            metrics["validation_error"] = e.to_string().into();
            (
                "INCONCLUSIVE".into(),
                "invalid_final_output".into(),
                Value::Null,
                metrics,
            )
        }
    }
}
pub fn codex_command(
    role: &Value,
    cwd: &Path,
    schema: &Path,
    final_path: &Path,
    grants: &[String],
    cache: &Path,
    cargo: &Path,
    npm: &Path,
    xdg: &Path,
    executable: &str,
    images: &[PathBuf],
) -> Result<Vec<String>> {
    let mut args: Vec<String> = vec![
        executable.into(),
        "exec".into(),
        "--strict-config".into(),
        "--ephemeral".into(),
        "--json".into(),
        "--model".into(),
        string(&role["model"])?.into(),
    ];
    let mut config = |s: String| {
        args.extend(["-c".into(), s]);
    };
    config(format!(
        "model_reasoning_effort={}",
        role["reasoningEffort"]
    ));
    config(format!("model_verbosity={}", role["verbosity"]));
    config("approval_policy=\"never\"".into());
    if !role["tokenLimit"].is_null() {
        for s in [
            "features.rollout_budget.enabled=true".into(),
            format!(
                "features.rollout_budget.limit_tokens={}",
                role["tokenLimit"]
            ),
            format!(
                "features.rollout_budget.reminder_at_remaining_tokens={}",
                role["reminders"]
            ),
            "features.rollout_budget.sampling_token_weight=1.0".into(),
            "features.rollout_budget.prefill_token_weight=1.0".into(),
        ] {
            config(s);
        }
    }
    args.extend(
        [
            "--disable",
            "multi_agent",
            "--disable",
            "goals",
            "--disable",
            "memories",
        ]
        .map(String::from),
    );
    if role["sandbox"] == "workspace-write" {
        let roots = format!(
            "{{ \".\" = \"write\", \".agents\" = {}, \".codex\" = {}, \".git\" = \"read\" }}",
            json!(if grants.iter().any(|g| g == ".agents") {
                "write"
            } else {
                "read"
            }),
            json!(if grants.iter().any(|g| g == ".codex") {
                "write"
            } else {
                "read"
            })
        );
        let filesystem = format!(
            "{{ \":root\" = \"read\", \":workspace_roots\" = {roots}, \":tmpdir\" = \"write\", \":slash_tmp\" = \"write\", {} = \"write\" }}",
            json!(cache)
        );
        for s in [
            "default_permissions=\"improve-executor-runtime\"".into(),
            format!("permissions.improve-executor-runtime.filesystem={filesystem}"),
            format!(
                "permissions.improve-executor-runtime.network.enabled={}",
                role["networkAccess"]
            ),
        ] {
            args.extend(["-c".into(), s]);
        }
        for (key, path) in [
            ("CARGO_HOME", cargo),
            ("npm_config_cache", npm),
            ("XDG_CACHE_HOME", xdg),
        ] {
            args.extend([
                "-c".into(),
                format!("shell_environment_policy.set.{key}={}", json!(path)),
            ]);
        }
    } else {
        args.extend(
            [
                "--sandbox",
                "read-only",
                "-c",
                "sandbox_workspace_write.network_access=false",
            ]
            .map(String::from),
        );
    }
    for image in images {
        args.extend(["--image".into(), image.display().to_string()]);
    }
    args.extend([
        "--output-schema".into(),
        schema.display().to_string(),
        "--output-last-message".into(),
        final_path.display().to_string(),
        "-C".into(),
        cwd.display().to_string(),
        "-".into(),
    ]);
    Ok(args)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn supervision_retains_output_bounds_events_and_stops_group() {
        let tmp = tempfile::tempdir().unwrap();
        let env = BTreeMap::from([
            ("HOME".into(), tmp.path().display().to_string()),
            (
                "XDG_STATE_HOME".into(),
                tmp.path().join("state").display().to_string(),
            ),
        ]);
        let cmd = |s: &str| vec!["sh".into(), "-c".into(), s.into()];
        let process = run_process(
            &cmd("printf 'partial'; printf 'diagnostic' >&2"),
            ProcessOptions::new(tmp.path(), &env, 5.0),
        )
        .unwrap();
        assert_eq!(process.status, 0);
        assert_eq!(process.stdout, b"partial");
        assert_eq!(process.stderr, b"diagnostic");
        let mut options = ProcessOptions::new(tmp.path(), &env, 5.0);
        options.stdout_limit = 4;
        let bounded = run_process(&cmd("printf 'abcdefgh'"), options).unwrap();
        assert_eq!(bounded.reason, "event_log_limit");
        assert_eq!(bounded.stdout, b"abcd");
        assert!(bounded.stdout_truncated);
        let timeout = run_process(
            &cmd("sleep 30"),
            ProcessOptions::new(tmp.path(), &env, 0.05),
        )
        .unwrap();
        assert_eq!(timeout.reason, "absolute_timeout");
        assert_ne!(timeout.status, 0);
        assert!(parse_events(b"{\"type\":\"thread.started\"}\n\n").is_err());
        let mut p = ProcessResult {
            status: 0,
            reason: "exit".into(),
            stdout: b"{\"type\":\"turn.completed\"}\n".to_vec(),
            stderr: Vec::new(),
            elapsed: 0.1,
            quiet_observed: false,
            stdout_truncated: false,
        };
        let report = br#"{"status":"STOPPED","steps":["checked"],"stoppedBecause":"missing input","filesChanged":[],"notes":[]}"#;
        let (outcome, _, _, metrics) = classify(&p, report, "executor", &[]);
        assert_eq!(outcome, "STOPPED");
        assert_eq!(metrics["token_usage"], Value::Null);
        assert_eq!(
            classify(&p, b"{broken", "executor", &[]).1,
            "invalid_final_output"
        );
        for usage in [
            Value::Null,
            json!({"input_tokens":0,"cached_input_tokens":0,"output_tokens":0}),
            json!({"input_tokens":20,"cached_input_tokens":5,"output_tokens":3}),
        ] {
            p.stdout = serde_json::to_vec(&json!({"type":"turn.completed","usage":usage})).unwrap();
            let (outcome, reason, actual, metrics) = classify(&p, report, "executor", &[]);
            assert_eq!(
                (outcome.as_str(), reason.as_str()),
                ("STOPPED", "completed")
            );
            assert_eq!(actual["stoppedBecause"], "missing input");
            assert_eq!(metrics["usage_observed"], !usage.is_null());
            assert_eq!(metrics["token_usage"], usage);
        }
        let invalid_stop =
            br#"{"status":"STOPPED","steps":[],"stoppedBecause":"","filesChanged":[],"notes":[]}"#;
        assert_eq!(
            classify(&p, invalid_stop, "executor", &[]).1,
            "invalid_final_output"
        );
        for events in [
            b"".as_slice(),
            b"broken",
            br#"{"type":"thread.started"}"#,
            br#"{"type":"turn.completed","type":"thread.started"}"#,
        ] {
            p.stdout = events.to_vec();
            assert_eq!(classify(&p, report, "executor", &[]).1, "invalid_event_log");
        }
        p.stdout = br#"{"type":"turn.completed"}"#.to_vec();
        p.reason = "absolute_timeout".into();
        p.stdout_truncated = true;
        let (_, reason, _, metrics) = classify(&p, report, "executor", &[]);
        assert_eq!(reason, "absolute_timeout");
        assert_eq!(metrics["event_evidence_valid"], false);
        p.reason = "exit".into();
        p.stdout_truncated = false;
        p.stdout = b"{\"type\":\"error\",\"message\":\"shared rollout token budget exhausted\"}\n"
            .to_vec();
        p.status = 1;
        assert_eq!(
            classify(&p, b"", "executor", &[]).1,
            "rollout_budget_exhausted"
        );
    }
}

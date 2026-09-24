"""Supervise one native Codex process and retain bounded raw evidence."""

from __future__ import annotations

import json
import os
import selectors
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from contracts import FINAL_LIMIT, strict_json, validate_executor, validate_review
from git_worktree import BoundaryError

EVENT_LIMIT = 32 * 1024 * 1024
DIAGNOSTIC_LIMIT = 1024 * 1024
HEARTBEAT_SECONDS = 60
QUIET_OBSERVATION_SECONDS = 180
KILL_GRACE_SECONDS = 5


@dataclass
class ProcessResult:
    status: int
    reason: str
    stdout: bytes
    stderr: bytes
    elapsed: float
    quiet_observed: bool
    stdout_truncated: bool = False


def _stop_group(process: subprocess.Popen[bytes], sig: int) -> None:
    try:
        os.killpg(process.pid, sig)
    except ProcessLookupError:
        pass


def run_process(argv: list[str], *, cwd: Path, env: dict[str, str], stdin: bytes = b"",
                deadline: float, stdout_limit: int = EVENT_LIMIT,
                stderr_limit: int = DIAGNOSTIC_LIMIT,
                on_start: Callable[[int], None] | None = None,
                on_stop: Callable[[int], None] | None = None,
                on_stdout: Callable[[bytes], object] | None = None,
                on_stderr: Callable[[bytes], object] | None = None) -> ProcessResult:
    """Bound output while running, kill the entire child process group on fuses."""
    started = time.monotonic()
    input_file = tempfile.TemporaryFile()
    input_file.write(stdin)
    input_file.seek(0)
    try:
        process = subprocess.Popen(argv, cwd=cwd, env=env, stdin=input_file,
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                   start_new_session=True)
    except FileNotFoundError as exc:
        raise BoundaryError(f"missing required command: {argv[0]}") from exc
    finally:
        input_file.close()
    assert process.stdout and process.stderr
    try:
        if on_start is not None:
            on_start(process.pid)
    except BaseException:
        _stop_group(process, signal.SIGKILL)
        process.wait()
        process.stdout.close()
        process.stderr.close()
        raise

    def stop(sig: int) -> None:
        _stop_group(process, sig)
        if on_stop is not None:
            on_stop(sig)

    watch = selectors.DefaultSelector()
    for stream in (process.stdout, process.stderr):
        os.set_blocking(stream.fileno(), False)
        watch.register(stream, selectors.EVENT_READ)
    output = bytearray()
    diagnostic = bytearray()
    reason = "exit"
    last_content = started
    last_heartbeat = started
    quiet_observed = False
    terminating_at: float | None = None
    previous_handlers: dict[int, Any] = {}
    cancelled = False
    stdout_truncated = False

    def cancel(_signum: int, _frame: Any) -> None:
        nonlocal cancelled
        cancelled = True

    for sig in (signal.SIGINT, signal.SIGTERM):
        try:
            previous_handlers[sig] = signal.signal(sig, cancel)
        except ValueError:
            pass
    try:
        while watch.get_map() or process.poll() is None:
            now = time.monotonic()
            if cancelled and terminating_at is None:
                reason = "caller_signal"
                stop(signal.SIGINT)
                terminating_at = now
            elif now - started >= deadline and terminating_at is None:
                reason = "absolute_timeout"
                stop(signal.SIGINT)
                terminating_at = now
            elif terminating_at is not None and now - terminating_at >= KILL_GRACE_SECONDS:
                stop(signal.SIGKILL)
            if now - last_content >= QUIET_OBSERVATION_SECONDS:
                quiet_observed = True
            if now - last_heartbeat >= HEARTBEAT_SECONDS:
                print("codex-improve: process active; no content logged", file=sys.stderr, flush=True)
                last_heartbeat = now
            for key, _ in watch.select(timeout=0.2):
                chunk = os.read(key.fd, 65536)
                if not chunk:
                    watch.unregister(key.fileobj)
                    continue
                last_content = time.monotonic()
                target = output if key.fileobj is process.stdout else diagnostic
                limit = stdout_limit if target is output else stderr_limit
                accepted = chunk[:max(0, limit - len(target))]
                target.extend(accepted)
                sink = on_stdout if target is output else on_stderr
                if accepted and sink is not None:
                    sink(accepted)
                if len(accepted) < len(chunk):
                    if target is output:
                        stdout_truncated = True
                    if target is output and terminating_at is None:
                        reason = "event_log_limit"
                        stop(signal.SIGINT)
                        terminating_at = time.monotonic()
            if process.poll() is not None and not watch.get_map():
                break
        status = process.wait()
    finally:
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)
        # The leader may have exited while another member still owns the group.
        if terminating_at is not None or process.poll() is None:
            stop(signal.SIGKILL)
        if process.poll() is None:
            process.wait()
        watch.close()
        process.stdout.close()
        process.stderr.close()
    return ProcessResult(status, reason, bytes(output), bytes(diagnostic),
                         time.monotonic() - started, quiet_observed, stdout_truncated)


def parse_events(raw: bytes) -> tuple[list[dict[str, Any]], dict[str, Any]]:
    events = []
    for line in raw.splitlines():
        event = strict_json(line)
        if not isinstance(event, dict) or not isinstance(event.get("type"), str):
            raise BoundaryError("invalid native JSONL event")
        events.append(event)
    if not events:
        raise BoundaryError("empty native JSONL stream")
    usage: dict[str, Any] | None = None
    counts = {"tool_events": 0, "command_executions": 0, "file_changes": 0,
              "mcp_tool_calls": 0, "web_searches": 0}
    for event in events:
        if event["type"] == "turn.completed" and isinstance(event.get("usage"), dict):
            source = event["usage"]
            values = (source.get("input_tokens"), source.get("cached_input_tokens"),
                      source.get("output_tokens"))
            if all(type(value) is int and value >= 0 for value in values):
                usage = dict(zip(("input_tokens", "cached_input_tokens", "output_tokens"), values))
        if event["type"].startswith("item."):
            counts["tool_events"] += 1
            item = event.get("item", {})
            if isinstance(item, dict):
                kind = item.get("type")
                if kind == "command_execution":
                    counts["command_executions"] += 1
                elif kind == "file_change":
                    counts["file_changes"] += 1
                elif kind == "mcp_tool_call":
                    counts["mcp_tool_calls"] += 1
                elif kind == "web_search":
                    counts["web_searches"] += 1
    return events, {"usage_observed": usage is not None, "token_usage": usage, **counts}


def classify(process: ProcessResult, final_raw: bytes, *, report_kind: str) -> tuple[str, str, Any, dict[str, Any]]:
    """Return (outcome, raw reason, valid report, content-free metrics)."""
    try:
        events, metrics = parse_events(process.stdout)
    except BoundaryError:
        events, metrics = [], {"usage_observed": False, "token_usage": None}
        event_valid = False
    else:
        event_valid = True
    metrics.update({"exit_status": process.status, "elapsed_seconds": round(process.elapsed, 3),
                    "quiet_observed": process.quiet_observed,
                    "event_evidence_valid": event_valid and not process.stdout_truncated,
                    "event_log_truncated": process.stdout_truncated})
    if process.reason != "exit":
        return "INCONCLUSIVE", process.reason, None, metrics
    if process.status != 0:
        if any(event.get("type") == "error" and event.get("message") ==
               "shared rollout token budget exhausted" for event in events):
            return "INCONCLUSIVE", "rollout_budget_exhausted", None, metrics
        return "INCONCLUSIVE", f"codex_exit_{process.status}", None, metrics
    if not event_valid:
        return "INCONCLUSIVE", "invalid_event_log", None, metrics
    if not any(event.get("type") == "turn.completed" for event in events):
        return "INCONCLUSIVE", "invalid_event_log", None, metrics
    if not final_raw:
        return "INCONCLUSIVE", "empty_final_output", None, metrics
    if len(final_raw) > FINAL_LIMIT:
        return "INCONCLUSIVE", "final_output_limit", None, metrics
    try:
        report = strict_json(final_raw)
        report = validate_executor(report) if report_kind == "executor" else validate_review(report)
    except BoundaryError:
        return "INCONCLUSIVE", "invalid_final_output", None, metrics
    if report_kind == "executor":
        return report["status"], "completed", report, metrics
    return report["verdict"], "completed", report, metrics


def codex_command(role: dict[str, Any], *, cwd: Path, schema: Path, final: Path,
                  grants: list[str], cache_root: Path, cargo: Path, npm: Path,
                  xdg: Path, codex_executable: str = "codex") -> list[str]:
    args = [codex_executable, "exec", "--strict-config", "--ephemeral", "--json",
            "--model", role["model"],
            "-c", f'model_reasoning_effort={json.dumps(role["reasoningEffort"])}',
            "-c", f'model_verbosity={json.dumps(role["verbosity"])}',
            "-c", 'approval_policy="never"']
    if role["tokenLimit"] is not None:
        args.extend(["-c", "features.rollout_budget.enabled=true",
                     "-c", f'features.rollout_budget.limit_tokens={role["tokenLimit"]}',
                     "-c", f'features.rollout_budget.reminder_at_remaining_tokens={json.dumps(role["reminders"])}',
                     "-c", "features.rollout_budget.sampling_token_weight=1.0",
                     "-c", "features.rollout_budget.prefill_token_weight=1.0"])
    args.extend(["--disable", "multi_agent", "--disable", "goals", "--disable", "memories"])
    if role["sandbox"] == "workspace-write":
        roots = {".": "write", ".agents": "write" if ".agents" in grants else "read",
                 ".codex": "write" if ".codex" in grants else "read", ".git": "read"}
        filesystem = {":root": "read", ":workspace_roots": roots, ":tmpdir": "write",
                      ":slash_tmp": "write", str(cache_root): "write"}
        toml_inline = "{ " + ", ".join(
            f'{json.dumps(key)} = {json.dumps(value) if isinstance(value, str) else "{ " + ", ".join(json.dumps(k) + " = " + json.dumps(v) for k, v in value.items()) + " }"}'
            for key, value in filesystem.items()
        ) + " }"
        args.extend(["-c", 'default_permissions="improve-executor-runtime"',
                     "-c", f"permissions.improve-executor-runtime.filesystem={toml_inline}",
                     "-c", "permissions.improve-executor-runtime.network.enabled=true"])
        for key, value in (("CARGO_HOME", cargo), ("npm_config_cache", npm), ("XDG_CACHE_HOME", xdg)):
            args.extend(["-c", f"shell_environment_policy.set.{key}={json.dumps(str(value))}"])
    else:
        args.extend(["--sandbox", "read-only", "-c", "sandbox_workspace_write.network_access=false"])
    args.extend(["--output-schema", str(schema), "--output-last-message", str(final),
                 "-C", str(cwd), "-"])
    return args

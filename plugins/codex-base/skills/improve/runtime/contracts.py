"""Small owned Improve contracts and authenticated private execution records."""

from __future__ import annotations

import hashlib
import hmac
import json
import os
import re
import secrets
import stat
import tempfile
import fcntl
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from git_worktree import BoundaryError

CONTRACT = "1.0.0-codex.17"
PLAN_LIMIT = 1024 * 1024
ENV_LIMIT = 16 * 1024
FINAL_LIMIT = 64 * 1024


def strict_json(raw: bytes | str) -> Any:
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result = {}
        for key, value in items:
            if key in result:
                raise BoundaryError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def nonfinite(value: str) -> None:
        raise BoundaryError(f"nonfinite JSON number: {value}")

    try:
        return json.loads(raw, object_pairs_hook=pairs, parse_constant=nonfinite)
    except (ValueError, UnicodeDecodeError) as exc:
        raise BoundaryError("invalid JSON") from exc


def _text(value: Any, *, nonblank: bool = True) -> bool:
    return isinstance(value, str) and (not nonblank or bool(value.strip()))


def _argument(value: Any) -> bool:
    return _text(value) and not any(ord(char) < 32 for char in value)


def _integer(value: Any, minimum: int, maximum: int) -> bool:
    return type(value) is int and minimum <= value <= maximum


def parse_plan(raw: bytes) -> dict[str, Any]:
    if not raw or len(raw) > PLAN_LIMIT:
        raise BoundaryError("plan size is invalid")
    try:
        lines = raw.decode("utf-8").splitlines()
    except UnicodeDecodeError as exc:
        raise BoundaryError("plan is not UTF-8") from exc
    declared = [line for line in lines if line.startswith("- **Improve contract**:")]
    if declared != [f"- **Improve contract**: `{CONTRACT}`"]:
        raise BoundaryError(f"plan must declare exactly one {CONTRACT} contract")
    opening = [i for i, line in enumerate(lines) if line == "```json codex-improve-environment"]
    if len(opening) != 1:
        raise BoundaryError("plan must contain exactly one environment block")
    start = opening[0]
    try:
        end = lines.index("```", start + 1)
    except ValueError as exc:
        raise BoundaryError("environment block is unterminated") from exc
    payload = "\n".join(lines[start + 1:end]).encode()
    if len(payload) > ENV_LIMIT:
        raise BoundaryError("environment block exceeds 16 KiB")
    value = strict_json(payload)
    if not isinstance(value, dict) or not set(value) <= {"version", "launcher", "probes", "cache"}:
        raise BoundaryError("invalid environment fields")
    if type(value.get("version")) is not int or value["version"] != 1:
        raise BoundaryError("environment version must be 1")
    launcher = value.get("launcher")
    if not isinstance(launcher, list) or not 1 <= len(launcher) <= 32 or not all(
        _argument(arg) for arg in launcher
    ):
        raise BoundaryError("invalid environment launcher")
    probes = value.get("probes")
    if not isinstance(probes, list) or len(probes) > 32:
        raise BoundaryError("invalid environment probes")
    for probe in probes:
        if not isinstance(probe, dict) or set(probe) != {"argv", "timeoutSeconds"}:
            raise BoundaryError("invalid environment probe")
        argv = probe["argv"]
        if not isinstance(argv, list) or not 1 <= len(argv) <= 32 or not all(_argument(arg) for arg in argv):
            raise BoundaryError("invalid environment probe argv")
        if not _integer(probe["timeoutSeconds"], 1, 3600):
            raise BoundaryError("invalid environment probe timeout")
    cache = value.get("cache", {"xdgScope": "execution"})
    if not isinstance(cache, dict) or set(cache) != {"xdgScope"} or cache["xdgScope"] not in (
        "execution", "worktree"
    ):
        raise BoundaryError("invalid environment cache scope")
    value["cache"] = cache
    return value


def read_roles(path: Path) -> dict[str, dict[str, Any]]:
    roles = strict_json(path.read_bytes())
    required = {"economy", "standard", "deep", "correctness", "elegance", "scout"}
    if not isinstance(roles, dict) or set(roles) != required:
        raise BoundaryError("invalid Improve roles")
    for name, role in roles.items():
        if not isinstance(role, dict) or set(role) != {
            "model", "reasoningEffort", "verbosity", "sandbox", "approval", "networkAccess",
            "tokenLimit", "reminders", "initialTimeout", "followupTimeout"
        }:
            raise BoundaryError(f"invalid role: {name}")
        if role["model"] not in ("gpt-6-sol", "gpt-6-luna") or role["reasoningEffort"] not in (
            "low", "medium", "high", "xhigh"
        ) or role["verbosity"] not in ("low", "medium") or role["approval"] != "never":
            raise BoundaryError(f"invalid model settings: {name}")
        writable = name in ("economy", "standard", "deep")
        if role["sandbox"] != ("workspace-write" if writable else "read-only") or role[
            "networkAccess"
        ] is not writable:
            raise BoundaryError(f"invalid role permissions: {name}")
        if role["tokenLimit"] is not None and not _integer(role["tokenLimit"], 1, 1000000):
            raise BoundaryError(f"invalid role budget: {name}")
        if not isinstance(role["reminders"], list) or not all(
            _integer(reminder, 1, 1000000) for reminder in role["reminders"]
        ) or not _integer(role["initialTimeout"], 1, 7200):
            raise BoundaryError(f"invalid role limits: {name}")
        if role["followupTimeout"] is not None and not _integer(role["followupTimeout"], 1, 7200):
            raise BoundaryError(f"invalid followup timeout: {name}")
    return roles


def validate_executor(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {
        "status", "steps", "stoppedBecause", "filesChanged", "notes"
    } or value["status"] not in ("COMPLETE", "STOPPED"):
        raise BoundaryError("invalid executor report shape")
    for key in ("steps", "filesChanged", "notes"):
        if not isinstance(value[key], list) or (key == "steps" and not value[key]) or not all(
            _text(item) for item in value[key]
        ):
            raise BoundaryError(f"invalid executor report {key}")
    reason = value["stoppedBecause"]
    if value["status"] == "COMPLETE" and reason is not None:
        raise BoundaryError("COMPLETE report has a stop reason")
    if value["status"] == "STOPPED" and (not _text(reason) or reason.strip().lower() == "none"):
        raise BoundaryError("STOPPED report lacks a reason")
    return value


def validate_review(value: Any) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != {
        "verdict", "summary", "findings", "coverage", "review_blockers", "deferred_acceptance"
    } or value["verdict"] not in ("APPROVE", "REVISE", "BLOCK") or not _text(value["summary"]):
        raise BoundaryError("invalid review verdict shape")
    fields = {
        "findings": ({"check", "severity", "location", "claim", "evidence", "action"}, False),
        "coverage": ({"check", "status", "evidence"}, True),
        "review_blockers": ({"item", "impact"}, False),
        "deferred_acceptance": ({"check", "owner", "reason", "evidence_required"}, False),
    }
    for key, (keys, required) in fields.items():
        items = value[key]
        if not isinstance(items, list) or (required and not items):
            raise BoundaryError(f"invalid review {key}")
        for item in items:
            if not isinstance(item, dict) or set(item) != keys or not all(
                _text(field) for field in item.values()
            ):
                raise BoundaryError(f"invalid review {key} entry")
    if any(item["severity"] not in ("critical", "high", "medium", "low") for item in value["findings"]):
        raise BoundaryError("invalid review severity")
    if any(item["status"] not in ("PASS", "FAIL", "BLOCKED") for item in value["coverage"]):
        raise BoundaryError("invalid review coverage status")
    verdict = value["verdict"]
    if verdict == "APPROVE" and (value["findings"] or value["review_blockers"] or any(
        item["status"] != "PASS" for item in value["coverage"]
    )):
        raise BoundaryError("APPROVE verdict contradicts findings")
    if verdict == "REVISE" and (not value["findings"] or value["review_blockers"] or not any(
        item["status"] == "FAIL" for item in value["coverage"]
    ) or any(item["status"] == "BLOCKED" for item in value["coverage"])):
        raise BoundaryError("REVISE verdict contradicts coverage")
    if verdict == "BLOCK" and not (value["review_blockers"] or any(
        item["status"] == "BLOCKED" for item in value["coverage"]
    )):
        raise BoundaryError("BLOCK verdict lacks a blocker")
    return value


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _private_stat(path: Path, directory: bool) -> None:
    try:
        info = path.lstat()
    except FileNotFoundError as exc:
        raise BoundaryError(f"private state path is missing: {path.name}") from exc
    if stat.S_ISLNK(info.st_mode) or info.st_uid != os.getuid() or (info.st_mode & 0o777) != (
        0o700 if directory else 0o600
    ) or (not stat.S_ISDIR(info.st_mode) if directory else not stat.S_ISREG(info.st_mode)):
        raise BoundaryError(f"private state path is unsafe: {path.name}")


def private_dir(path: Path) -> Path:
    if path.is_symlink():
        raise BoundaryError("private state directory is a symlink")
    try:
        path.mkdir(mode=0o700)
    except FileExistsError:
        pass
    _private_stat(path, True)
    return path


def private_read(path: Path) -> bytes:
    _private_stat(path, False)
    return path.read_bytes()


def private_append(path: Path):
    descriptor = os.open(path, os.O_WRONLY | os.O_APPEND | os.O_NOFOLLOW)
    try:
        info = os.fstat(descriptor)
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or (
            info.st_mode & 0o777
        ) != 0o600:
            raise BoundaryError(f"private state path is unsafe: {path.name}")
        return os.fdopen(descriptor, "ab", buffering=0)
    except BaseException:
        os.close(descriptor)
        raise


def atomic_private(path: Path, raw: bytes) -> None:
    if path.exists() or path.is_symlink():
        _private_stat(path, False)
    descriptor, name = tempfile.mkstemp(prefix=".tmp-", dir=path.parent)
    try:
        os.fchmod(descriptor, 0o600)
        with os.fdopen(descriptor, "wb") as output:
            output.write(raw)
            output.flush()
            os.fsync(output.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


class StateStore:
    def __init__(self, base: Path | None = None):
        state_home = base or Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state"))
        if state_home.is_symlink():
            raise BoundaryError("state home is a symlink")
        state_home.mkdir(parents=True, exist_ok=True, mode=0o700)
        parent_info = state_home.lstat()
        if not stat.S_ISDIR(parent_info.st_mode) or parent_info.st_uid != os.getuid():
            raise BoundaryError("state home is not a physical user-owned directory")
        self.root = private_dir(state_home / "codex-improve-v17")
        self.executions = private_dir(self.root / "executions")
        self.worktrees = private_dir(self.root / "worktrees")
        self.cache = private_dir(self.root / "cache")
        key_path = self.root / "key"
        if not key_path.exists() and not key_path.is_symlink():
            atomic_private(key_path, secrets.token_bytes(32))
        self.key = private_read(key_path)
        if len(self.key) != 32:
            raise BoundaryError("private state key is invalid")

    def new_id(self) -> str:
        return secrets.token_hex(16)

    def path(self, execution_id: str) -> Path:
        if not re.fullmatch(r"[0-9a-f]{32}", execution_id):
            raise BoundaryError("invalid execution ID")
        return self.executions / execution_id

    @contextmanager
    def locked(self, execution_id: str):
        location = self.path(execution_id)
        _private_stat(location, True)
        descriptor = os.open(location, os.O_RDONLY | os.O_DIRECTORY)
        try:
            fcntl.flock(descriptor, fcntl.LOCK_EX)
            yield self.load(execution_id)
        finally:
            fcntl.flock(descriptor, fcntl.LOCK_UN)
            os.close(descriptor)

    def create(self, record: dict[str, Any], plan: bytes, prompt: bytes) -> None:
        location = self.path(record["id"])
        if location.exists() or location.is_symlink():
            raise BoundaryError("execution ID already exists")
        private_dir(location)
        atomic_private(location / "plan.md", plan)
        atomic_private(location / "prompt.txt", prompt)
        for name in ("events.jsonl", "final.json", "diagnostics.txt", "launcher-diagnostics.txt", "preflight.txt"):
            atomic_private(location / name, b"")
        record["plan_hash"] = digest(plan)
        record["prompt_hash"] = digest(prompt)
        self.save(record)

    def save(self, record: dict[str, Any]) -> None:
        location = self.path(record["id"])
        _private_stat(location, True)
        raw = json.dumps(record, sort_keys=True, separators=(",", ":"), allow_nan=False).encode()
        mac = hmac.new(self.key, raw, hashlib.sha256).hexdigest().encode()
        atomic_private(location / "record.json", raw + b"\n" + mac + b"\n")

    def load(self, execution_id: str) -> dict[str, Any]:
        location = self.path(execution_id)
        _private_stat(location, True)
        raw = private_read(location / "record.json")
        try:
            payload, mac, empty = raw.split(b"\n")
        except ValueError as exc:
            raise BoundaryError("private record is malformed") from exc
        if empty or not hmac.compare_digest(mac, hmac.new(self.key, payload, hashlib.sha256).hexdigest().encode()):
            raise BoundaryError("private record authentication failed")
        record = strict_json(payload)
        if not isinstance(record, dict) or record.get("id") != execution_id:
            raise BoundaryError("private record identity mismatch")
        if digest(private_read(location / "plan.md")) != record.get("plan_hash") or digest(
            private_read(location / "prompt.txt")
        ) != record.get("prompt_hash"):
            raise BoundaryError("private plan or prompt hash mismatch")
        parse_plan(private_read(location / "plan.md"))
        return record

    def write_artifact(self, execution_id: str, name: str, raw: bytes) -> None:
        if name not in {"events.jsonl", "final.json", "diagnostics.txt", "launcher-diagnostics.txt",
                        "preflight.txt", "metrics.json"}:
            raise BoundaryError("invalid artifact name")
        atomic_private(self.path(execution_id) / name, raw)

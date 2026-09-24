"""Focused .17 runtime fixtures: real Git/Worktrunk and fake native Codex."""

from __future__ import annotations

import json
import os
import runpy
import stat
import subprocess
import sys
import tempfile
import threading
import signal
import time
import unittest
from pathlib import Path
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SKILL_ROOT = Path(os.environ.get("CODEX_IMPROVE_SKILL_ROOT", ROOT / "src/improve"))
RUNTIME = SKILL_ROOT / "runtime"
CLI = SKILL_ROOT / "scripts/codex-improve"
sys.path.insert(0, str(RUNTIME))

from contracts import StateStore, parse_plan, read_roles
from git_worktree import (BoundaryError, candidate, checkpoint, copy_ignored,
                          create_worktree, git, integrate_exact, require_candidate,
                          require_oid, validate_worktree, wt)
from transport import ProcessResult, classify, codex_command, run_process

CLI_FUNCTIONS = runpy.run_path(str(CLI))


def run(*args: str | Path, cwd: Path | None = None, env: dict | None = None,
        check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run([str(arg) for arg in args], cwd=cwd, env=env, text=True,
                          capture_output=True, check=check)


class Fixture(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="improve-runtime-")
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.repo = self.root / "repo"
        self.repo.mkdir()
        run("git", "init", "-q", self.repo)
        run("git", "-C", self.repo, "config", "user.name", "Fixture")
        run("git", "-C", self.repo, "config", "user.email", "fixture@example.invalid")
        (self.repo / "tracked.txt").write_text("base\n")
        run("git", "-C", self.repo, "add", "tracked.txt")
        run("git", "-C", self.repo, "commit", "-qm", "base")
        self.base = git(self.repo, "rev-parse", "HEAD")
        self.state_home = self.root / "state"
        self.state_home.mkdir(mode=0o700)
        self.store = StateStore(self.state_home)
        self.env = dict(os.environ, XDG_STATE_HOME=str(self.state_home), HOME=str(self.root))
        self.bin = self.root / "bin"
        self.bin.mkdir()
        fake = self.bin / "codex"
        fake.write_text(f"#!{sys.executable}\n" + """\
import json, os, pathlib, signal, subprocess, sys, time
args=sys.argv[1:]
if '--version' in args:
    print('codex-cli 0.156.1'); sys.exit(0)
if os.environ.get('FAKE_CAPTURE'):
    pathlib.Path(os.environ['FAKE_CAPTURE']).write_text(json.dumps(args))
mode=os.environ.get('FAKE_MODE','complete')
if mode == 'sleep':
    time.sleep(10)
if mode == 'nested_ignore':
    print(json.dumps({'type':'thread.started','thread_id':'partial-evidence'}),flush=True)
    print('partial-diagnostic',file=sys.stderr,flush=True)
    if os.environ.get('FAKE_WORKER_PID'):
        pathlib.Path(os.environ['FAKE_WORKER_PID']).write_text(str(os.getppid()))
    child=subprocess.Popen([sys.executable,'-c',
      'import signal,time;signal.signal(signal.SIGINT,signal.SIG_IGN);time.sleep(30)'],
      stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
    pathlib.Path(os.environ['FAKE_CHILD_PID']).write_text(str(child.pid))
    pathlib.Path(os.environ['FAKE_CODEX_PID']).write_text(str(os.getpid()))
    signal.signal(signal.SIGINT,signal.SIG_IGN)
    time.sleep(30)
if mode == 'overflow':
    print('x'*33000000, flush=True)
    time.sleep(10)
if mode == 'budget':
    print(json.dumps({'type':'error','message':'shared rollout token budget exhausted'}),flush=True)
    sys.exit(1)
if mode == 'exit124':
    print(json.dumps({'type':'thread.started'}),flush=True)
    sys.exit(124)
print(json.dumps({'type':'thread.started'}),flush=True)
print(json.dumps({'type':'turn.completed','usage':{'input_tokens':10,'cached_input_tokens':2,'output_tokens':3}}),flush=True)
final=pathlib.Path(args[args.index('--output-last-message')+1])
if mode == 'corrupt':
    final.write_text('{broken')
elif mode == 'empty':
    pass
elif mode == 'oversized':
    final.write_text('x'*65537)
elif mode == 'review':
    final.write_text(json.dumps({'verdict':'APPROVE','summary':'Checked','findings':[],
      'coverage':[{'check':'fixture','status':'PASS','evidence':'fixture'}],
      'review_blockers':[],'deferred_acceptance':[]}))
else:
    final.write_text(json.dumps({'status':'COMPLETE','steps':['done'],
      'stoppedBecause':None,'filesChanged':[],'notes':[]}))
""")
        fake.chmod(0o755)
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]

    def worktree(self, name="fixture"):
        return create_worktree(self.repo, f"codex/improve-{name}", self.base, self.store.worktrees)

    def cli(self, *args, env=None, check=False):
        values = dict(self.env)
        if env:
            values.update(env)
        result = run(sys.executable, "-B", CLI, *args, env=values, check=False)
        if check and result.returncode:
            record = json.loads(result.stdout)
            diagnostics = Path(record["artifacts"]["diagnostics"]).read_text()
            self.fail(f"CLI failed: {result.stdout}\n{result.stderr}\n{diagnostics}")
        return result

    def plan(self, probes=None, contract="1.0.0-codex.17", launcher=None):
        plan = self.root / "plan.md"
        plan.write_text(f"- **Improve contract**: `{contract}`\n"
                        "```json codex-improve-environment\n" +
                        json.dumps({"version": 1, "launcher": launcher or ["env"], "probes": probes or []}) +
                        "\n```\n")
        return plan


class GitAndWorktrunk(Fixture):
    def test_scout_accepts_existing_checkouts_without_mutating_them(self):
        linked = self.root / "unrelated"
        detached = self.root / "detached"
        run("git", "-C", self.repo, "worktree", "add", "-qb", "unrelated", linked)
        run("git", "-C", self.repo, "worktree", "add", "-q", "--detach", detached)
        dossier = self.plan()
        for path in (self.repo, linked, detached):
            with self.subTest(path=path):
                (path / "tracked.txt").write_bytes(b"staged\n")
                run("git", "-C", path, "add", "tracked.txt")
                (path / "tracked.txt").write_bytes(b"unstaged\n")
                (path / "untracked.txt").write_bytes(b"untracked\n")
                index = Path(git(path, "rev-parse", "--path-format=absolute", "--git-path", "index"))
                before = (git(path, "rev-parse", "HEAD"), index.read_bytes(),
                          (path / "tracked.txt").read_bytes(), (path / "untracked.txt").read_bytes())
                tree = candidate(validate_worktree(path, owned=False))[1]
                reported = self.cli("candidate", path, check=True)
                self.assertEqual(json.loads(reported.stdout), {"head": before[0], "tree": tree})
                capture = self.root / f"{path.name}-command.json"
                result = self.cli("scout", path, tree, dossier,
                                  env={"FAKE_CAPTURE": str(capture)}, check=True)
                record = json.loads(result.stdout)
                self.assertEqual((record["outcome"], record["output_candidate_tree"]),
                                 ("COMPLETE", tree))
                args = json.loads(capture.read_text())
                self.assertIn("read-only", args)
                self.assertIn("sandbox_workspace_write.network_access=false", args)
                self.assertNotIn("workspace-write", args)
                self.assertEqual((git(path, "rev-parse", "HEAD"), index.read_bytes(),
                                  (path / "tracked.txt").read_bytes(),
                                  (path / "untracked.txt").read_bytes()), before)
                self.assertEqual(self.cli("checkpoint", path, tree,
                                          "--message", "feat: blocked").returncode, 2)
        tree = candidate(validate_worktree(self.repo, owned=False))[1]
        self.assertEqual(self.cli("scout", self.repo,
                                  git(self.repo, "rev-parse", "HEAD^{tree}"), dossier).returncode, 2)
        drifted = self.cli("scout", self.repo, tree, dossier,
                           env={"FAKE_CAPTURE": "concurrent-change.txt"}, check=True)
        self.assertEqual(json.loads(drifted.stdout)["reason"], "postrun_candidate_drift")

    def test_real_lifecycle_candidate_and_copy(self):
        (self.repo / ".gitignore").write_text("*.bin\n")
        (self.repo / ".worktreeinclude").write_text("cache.bin\n")
        run("git", "-C", self.repo, "add", ".gitignore", ".worktreeinclude")
        run("git", "-C", self.repo, "commit", "-qm", "include")
        self.base = git(self.repo, "rev-parse", "HEAD")
        (self.repo / "caller-only.txt").write_text("dirty")
        (self.repo / "cache.bin").write_text("cached")
        worktree = self.worktree()
        root_info = worktree.path.lstat()
        self.assertTrue(stat.S_ISDIR(root_info.st_mode))
        self.assertEqual(root_info.st_uid, os.getuid())
        self.assertEqual(stat.S_IMODE(root_info.st_mode), 0o700)
        self.assertFalse((worktree.path / "caller-only.txt").exists())
        source = validate_worktree(self.repo, owned=False)
        copy_ignored(source, worktree, ["cache.bin"])
        self.assertEqual((worktree.path / "cache.bin").read_text(), "cached")
        with self.assertRaisesRegex(BoundaryError, "include set"):
            copy_ignored(source, worktree, ["other.bin"])
        (worktree.path / "tracked.txt").write_text("modified")
        run("git", "-C", worktree.path, "add", "tracked.txt")
        (worktree.path / "tracked.txt").write_text("unstaged")
        (worktree.path / "new.txt").write_text("new")
        before = git(worktree.path, "write-tree")
        head, tree = candidate(worktree)
        self.assertEqual(head, self.base)
        self.assertNotEqual(before, tree)
        self.assertEqual(git(worktree.path, "write-tree"), before)
        with self.assertRaisesRegex(BoundaryError, "full object ID"):
            require_candidate(worktree, tree[:8])
        with self.assertRaisesRegex(BoundaryError, "does not match"):
            require_candidate(worktree, git(worktree.path, "rev-parse", "HEAD^{tree}"))
        run("git", "-C", worktree.path, "reset", "-q", "--hard")
        (worktree.path / "new.txt").unlink()
        result = wt(worktree.path, "remove", str(worktree.path), "--no-delete-branch",
                    "--no-hooks", "--foreground", "--format=json")
        self.assertIsInstance(result, (dict, list))
        self.assertFalse(worktree.path.exists())
        self.assertEqual(git(self.repo, "rev-parse", f"refs/heads/{worktree.branch}"), self.base)

    def test_checkpoint_hooks_and_exact_integration(self):
        worktree = self.worktree()
        (worktree.path / "tracked.txt").write_text("reviewed")
        tree = candidate(worktree)[1]
        hooks = worktree.common_dir / "hooks"
        hook = hooks / "pre-commit"
        hook.write_text("#!/bin/sh\nexit 1\n")
        hook.chmod(0o755)
        with self.assertRaises(BoundaryError):
            checkpoint(worktree, tree, "feat: reviewed")
        self.assertEqual(git(worktree.path, "rev-parse", "HEAD"), self.base)
        hook.write_text("#!/bin/sh\nprintf 'mutated' > tracked.txt\ngit add tracked.txt\n")
        with self.assertRaisesRegex(BoundaryError, "changed the reviewed tree"):
            checkpoint(worktree, tree, "feat: reviewed")
        hook.unlink()
        (worktree.path / "tracked.txt").write_text("reviewed")
        tree = candidate(worktree)[1]
        oid = checkpoint(worktree, tree, "feat: reviewed")
        self.assertEqual(git(worktree.path, "rev-parse", "HEAD"), oid)
        with self.assertRaisesRegex(BoundaryError, "full object ID"):
            integrate_exact(self.repo, oid[:8], self.base)
        with self.assertRaisesRegex(BoundaryError, "full object ID"):
            integrate_exact(self.repo, oid, self.base[:8])
        (self.repo / "unrelated.txt").write_text("keep")
        merged = integrate_exact(self.repo, oid, self.base)
        self.assertEqual(git(self.repo, "rev-parse", f"{merged}^2"), oid)
        self.assertEqual((self.repo / "unrelated.txt").read_text(), "keep")
        with self.assertRaisesRegex(BoundaryError, "drifted"):
            integrate_exact(self.repo, oid, self.base)

    def test_integration_refuses_ignored_collision(self):
        (self.repo / ".gitignore").write_text("collision.bin\n")
        run("git", "-C", self.repo, "add", ".gitignore")
        run("git", "-C", self.repo, "commit", "-qm", "ignore")
        self.base = git(self.repo, "rev-parse", "HEAD")
        worktree = self.worktree()
        (worktree.path / "collision.bin").write_text("reviewed")
        run("git", "-C", worktree.path, "add", "-f", "collision.bin")
        oid = checkpoint(worktree, candidate(worktree)[1], "feat: reviewed")
        (self.repo / "collision.bin").write_text("local ignored")
        with self.assertRaisesRegex(BoundaryError, "dirt overlaps"):
            integrate_exact(self.repo, oid, self.base)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), self.base)


class ContractsAndTransport(Fixture):
    def test_status_reports_live_and_finished_records(self):
        worktree = self.worktree()
        plan = self.plan().read_bytes()
        record = CLI_FUNCTIONS["_record"](
            self.store, role="standard", worktree=worktree.path, common_dir=worktree.common_dir,
            branch=worktree.branch, head=worktree.head, tree=candidate(worktree)[1],
            grants=[], kind="execute")
        record["environment_settings"] = parse_plan(plan)
        record["role_settings"] = read_roles(SKILL_ROOT / "config/roles.json")["standard"]
        self.store.create(record, plan, b"assigned prompt")
        for phase in ("preparing", "preflight", "executing"):
            record["phase"] = phase
            self.store.save(record)
            result = self.cli("status", record["id"], check=True)
            status = json.loads(result.stdout)
            self.assertEqual((status["phase"], status["candidate_tree"]),
                             (phase, record["candidate_tree"]))
            self.assertIsNone(status["output_candidate_tree"])
            self.assertIsNone(status["report"])
            self.assertIsNone(status["artifacts"])
            self.assertFalse(status["closeout_eligible"])
        finished = json.loads(self.cli("execute", self.plan(), self.repo, check=True).stdout)
        status = json.loads(self.cli("status", finished["id"], check=True).stdout)
        for key in ("phase", "outcome", "reason", "candidate_tree", "output_candidate_tree",
                    "report", "artifacts", "closeout_eligible"):
            self.assertEqual(status[key], finished[key])

    def test_plan_rejection_and_private_state_tamper(self):
        with self.assertRaisesRegex(BoundaryError, "contract"):
            parse_plan(self.plan(contract="1.0.0-codex.16").read_bytes())
        raw = b'- **Improve contract**: `1.0.0-codex.17`\n```json codex-improve-environment\n{"version":1,"version":1,"launcher":["env"],"probes":[]}\n```\n'
        with self.assertRaises(BoundaryError):
            parse_plan(raw)
        raw = raw.replace(b'"version":1,"version":1', b'"version":true')
        with self.assertRaises(BoundaryError):
            parse_plan(raw)
        result = self.cli("execute", self.plan(), self.repo)
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(result.stdout)
        self.assertEqual(record["outcome"], "COMPLETE")
        location = self.store.path(record["id"])
        self.assertEqual(stat.S_IMODE(location.stat().st_mode), 0o700)
        self.assertEqual(stat.S_IMODE((location / "plan.md").stat().st_mode), 0o600)
        (location / "plan.md").write_text("tampered")
        self.assertNotEqual(self.cli("status", record["id"]).returncode, 0)

    def test_preflight_resume_once_and_mutation(self):
        probe = self.root / "probe.py"
        probe.write_text("import sys;sys.exit(1)\n")
        plan = self.plan([{"argv": [sys.executable, str(probe)], "timeoutSeconds": 2}])
        result = self.cli("execute", plan, self.repo)
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(result.stdout)
        self.assertEqual(record["reason"], "environment_preflight_failed")
        probe.write_text("pass\n")
        resumed = self.cli("resume", record["id"])
        self.assertEqual(resumed.returncode, 0, resumed.stderr)
        self.assertEqual(json.loads(resumed.stdout)["outcome"], "COMPLETE")
        self.assertNotEqual(self.cli("resume", record["id"]).returncode, 0)
        probe.write_text("from pathlib import Path;Path('changed.txt').write_text('x')\n")
        mutated = self.cli("execute", plan, self.repo)
        self.assertEqual(mutated.returncode, 0, mutated.stderr)
        self.assertEqual(json.loads(mutated.stdout)["reason"], "environment_preflight_mutated_candidate")

    def test_root_symlink_and_readonly_review(self):
        worktree = self.worktree()
        (worktree.path / ".agents").symlink_to("missing")
        plan = self.plan()
        # A granted dangling root is refused before invoking a model.
        result = self.cli("review", "correctness", worktree.path, candidate(worktree)[1], plan)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["reason"], "environment_preflight_mutated_candidate")
        (worktree.path / ".agents").unlink()
        capture = self.root / "command.json"
        result = self.cli("review", "correctness", worktree.path, candidate(worktree)[1], plan,
                          env={"FAKE_MODE": "review", "FAKE_CAPTURE": str(capture)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["outcome"], "APPROVE")
        args = json.loads(capture.read_text())
        self.assertIn("read-only", args)
        self.assertNotIn("workspace-write", args)
        self.assertIn("--strict-config", args)

    def test_transport_budget_corruption_timeout_signal_and_cap(self):
        for mode, expected in (("budget", "rollout_budget_exhausted"),
                               ("corrupt", "invalid_final_output"),
                               ("empty", "empty_final_output"),
                               ("oversized", "final_output_limit"),
                               ("exit124", "codex_exit_124")):
            result = self.cli("execute", self.plan(), self.repo, env={"FAKE_MODE": mode})
            self.assertEqual(result.returncode, 1, result.stderr)
            record = json.loads(result.stdout)
            self.assertEqual(record["reason"], expected)
            if mode in ("corrupt", "empty", "oversized"):
                self.assertTrue(record["closeout_eligible"])
        process = run_process([sys.executable, "-c", "import time;time.sleep(10)"],
                              cwd=self.repo, env=self.env, deadline=0.1)
        self.assertEqual(process.reason, "absolute_timeout")
        self.assertNotEqual(process.status, 0)
        process = run_process([sys.executable, "-c", "print('x'*10000)"],
                              cwd=self.repo, env=self.env, deadline=2, stdout_limit=100)
        self.assertEqual(process.reason, "event_log_limit")
        timer = threading.Timer(0.2, lambda: os.kill(os.getpid(), signal.SIGTERM))
        timer.start()
        try:
            process = run_process([sys.executable, "-c", "import time;time.sleep(10)"],
                                  cwd=self.repo, env=self.env, deadline=2)
        finally:
            timer.cancel()
            timer.join()
        self.assertEqual(process.reason, "caller_signal")
        fake = ProcessResult(124, "exit", b'{"type":"thread.started"}\n', b"", 0.1, False)
        self.assertEqual(classify(fake, b"", report_kind="executor")[1], "codex_exit_124")

    def test_closeout_requires_events_and_captured_candidate(self):
        record = json.loads(self.cli("execute", self.plan(), self.repo, check=True).stdout)
        finish = CLI_FUNCTIONS["_finish"]
        for reason in ("rollout_budget_exhausted", "absolute_timeout", "empty_final_output",
                       "invalid_final_output", "final_output_limit"):
            metrics = {"event_evidence_valid": True}
            finish(self.store, record, "INCONCLUSIVE", reason, metrics)
            self.assertTrue(record["closeout_eligible"], reason)
            finish(self.store, record, "INCONCLUSIVE", reason, {"event_evidence_valid": False})
            self.assertFalse(record["closeout_eligible"], reason)
        for raw, truncated in ((b"broken\n", False),
                               (b'{"type":"thread.started"}\n', True)):
            process = ProcessResult(130, "absolute_timeout", raw, b"", 0.1, False, truncated)
            outcome, reason, _, metrics = classify(process, b"", report_kind="executor")
            self.assertEqual((outcome, reason), ("INCONCLUSIVE", "absolute_timeout"))
            self.assertFalse(metrics["event_evidence_valid"])
            finish(self.store, record, outcome, reason, metrics)
            self.assertFalse(record["closeout_eligible"])
        metrics = {"event_evidence_valid": True, "exit_status": 130}
        def failed_capture(_path, *, owned):
            raise BoundaryError("capture failed")
        with patch.dict(finish.__globals__, {"validate_worktree": failed_capture}):
            finish(self.store, record, "INCONCLUSIVE", "absolute_timeout", metrics)
        self.assertEqual(record["reason"], "absolute_timeout")
        self.assertEqual(metrics["exit_status"], 130)
        self.assertIsNone(record["output_candidate_tree"])
        self.assertFalse(record["closeout_eligible"])

    def test_resume_retains_review_and_scout_prompt_role_and_schema(self):
        for kind, role in (("review", "correctness"), ("scout", "scout")):
            worktree = self.worktree(kind)
            probe = self.root / f"{kind}-probe.py"
            probe.write_text("import sys;sys.exit(1)\n")
            plan = self.plan([{"argv": [sys.executable, str(probe)], "timeoutSeconds": 2}]).read_bytes()
            record = CLI_FUNCTIONS["_record"](
                self.store, role=role, worktree=worktree.path, common_dir=worktree.common_dir,
                branch=worktree.branch, head=worktree.head, tree=candidate(worktree)[1],
                grants=[], kind=kind)
            assigned = (f"Assigned {kind} prompt and schema.\n").encode()
            with patch.dict(os.environ, self.env):
                initial = CLI_FUNCTIONS["start"](self.store, record, plan, assigned)
            self.assertEqual(initial["reason"], "environment_preflight_failed")
            probe.write_text("pass\n")
            capture = self.root / f"{kind}-command.json"
            resumed = self.cli("resume", initial["id"], env={
                "FAKE_MODE": "review" if kind == "review" else "complete",
                "FAKE_CAPTURE": str(capture)})
            self.assertEqual(resumed.returncode, 0, resumed.stderr)
            followup = json.loads(resumed.stdout)
            self.assertEqual((followup["kind"], followup["role"], followup["grants"]),
                             (kind, role, []))
            self.assertEqual((self.store.path(followup["id"]) / "prompt.txt").read_bytes(), assigned)
            args = json.loads(capture.read_text())
            self.assertIn("read-only", args)
            schema = args[args.index("--output-schema") + 1]
            self.assertTrue(schema.endswith("review-verdict.schema.json" if kind == "review"
                                            else "executor-report.schema.json"))
            self.assertEqual(followup["role_settings"], initial["role_settings"])
            self.assertNotEqual(self.cli("resume", initial["id"]).returncode, 0)

    def test_snapshot_rejects_private_role_change_and_review_revision(self):
        worktree = self.worktree()
        result = self.cli("review", "correctness", worktree.path, candidate(worktree)[1],
                          self.plan(), env={"FAKE_MODE": "review"})
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(result.stdout)
        private_roles = self.root / "roles.json"
        roles = json.loads((SKILL_ROOT / "config/roles.json").read_text())
        roles["correctness"]["initialTimeout"] += 1
        private_roles.write_text(json.dumps(roles))
        verify = CLI_FUNCTIONS["_verify_snapshot"]
        with patch.dict(verify.__globals__, {"ROLES": private_roles}):
            with self.assertRaisesRegex(BoundaryError, "settings changed"):
                verify(self.store, record)
        findings = self.root / "findings.md"
        findings.write_text("Finding: review a concrete behavior.\n")
        attempt = self.cli("revise", record["id"], findings,
                           "--expected-tree", record["output_candidate_tree"])
        self.assertEqual(attempt.returncode, 2)
        self.assertFalse(self.store.load(record["id"])["consumed"])

    def test_missing_launcher_probe_and_worker_command_finish(self):
        missing = str(self.root / "missing-command")
        launcher = json.loads(self.cli("execute", self.plan(launcher=[missing]), self.repo).stdout)
        self.assertEqual((launcher["phase"], launcher["reason"]), ("finished", "launcher_error"))
        self.assertTrue(Path(launcher["artifacts"]["diagnostics"]).read_text())
        self.assertIn("missing required command", Path(launcher["artifacts"]["launcher_diagnostics"]).read_text())
        probe = json.loads(self.cli("execute", self.plan([
            {"argv": [missing], "timeoutSeconds": 1}]), self.repo).stdout)
        self.assertEqual((probe["phase"], probe["reason"]),
                         ("finished", "environment_preflight_failed"))
        self.assertIn("missing required command", Path(probe["artifacts"]["preflight"]).read_text())
        worktree = self.worktree()
        plan = self.plan().read_bytes()
        worker = CLI_FUNCTIONS["_record"](
            self.store, role="standard", worktree=worktree.path, common_dir=worktree.common_dir,
            branch=worktree.branch, head=worktree.head, tree=candidate(worktree)[1],
            grants=[], kind="execute")
        worker["environment_settings"] = parse_plan(plan)
        worker["role_settings"] = read_roles(SKILL_ROOT / "config/roles.json")["standard"]
        self.store.create(worker, plan, b"assigned prompt")
        worker_fn = CLI_FUNCTIONS["_worker"]
        def unavailable(*_args):
            raise BoundaryError("missing required command: codex")
        with patch.dict(worker_fn.__globals__, {"require_tools": unavailable}), patch.dict(os.environ, self.env):
            worker = worker_fn(self.store, worker["id"])
        self.assertEqual((worker["phase"], worker["outcome"], worker["reason"]),
                         ("finished", "INCONCLUSIVE", "worker_error"))
        self.assertIn("missing required command", Path(worker["artifacts"]["diagnostics"]).read_text())
        self.assertIsNotNone(worker["output_candidate_tree"])

    def test_launcher_failure_preserves_private_diagnostics(self):
        result = self.cli("execute", self.plan(launcher=[
            "sh", "-c", "printf launcher_failure_marker >&2; exit 7", "sh"]), self.repo)
        self.assertEqual(result.returncode, 1, result.stderr)
        record = json.loads(result.stdout)
        self.assertEqual((record["outcome"], record["reason"]),
                         ("INCONCLUSIVE", "launcher_exit_7"))
        self.assertEqual(result.stderr, "")
        self.assertEqual(Path(record["artifacts"]["diagnostics"]).read_bytes(), b"")
        path = Path(record["artifacts"]["launcher_diagnostics"])
        self.assertEqual(path.read_bytes(), b"launcher_failure_marker")
        self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
        self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)

    def test_edited_output_revision_and_stale_input(self):
        initial = json.loads(self.cli("execute", self.plan(), self.repo,
                                      env={"FAKE_CAPTURE": "model-change.txt"}, check=True).stdout)
        worktree = Path(initial["worktree"])
        current = json.loads(self.cli("candidate", worktree, check=True).stdout)["tree"]
        self.assertNotEqual(initial["candidate_tree"], current)
        self.assertEqual(initial["output_candidate_tree"], current)
        self.assertEqual(initial["report"]["status"], "COMPLETE")
        self.assertTrue(Path(initial["artifacts"]["final"]).is_file())
        findings = self.root / "findings.md"
        findings.write_text("Finding: correct the concrete reviewed behavior.\n")
        revised = self.cli("revise", initial["id"], findings, "--expected-tree", current)
        self.assertEqual(revised.returncode, 0, revised.stderr)
        self.assertEqual(json.loads(revised.stdout)["parent"], initial["id"])
        self.assertNotEqual(self.cli("revise", initial["id"], findings,
                                     "--expected-tree", current).returncode, 0)
        second = json.loads(self.cli("execute", self.plan(), self.repo, check=True).stdout)
        (Path(second["worktree"]) / "later.txt").write_text("external drift")
        self.assertNotEqual(self.cli("revise", second["id"], findings,
                                     "--expected-tree", second["output_candidate_tree"]).returncode, 0)
        self.assertFalse(self.store.load(second["id"])["consumed"])

    def test_recovery_slices_and_replay(self):
        initial_result = self.cli("execute", self.plan(), self.repo,
                                  env={"FAKE_MODE": "budget", "FAKE_CAPTURE": "model-change.txt"})
        self.assertEqual(initial_result.returncode, 1, initial_result.stderr)
        initial = json.loads(initial_result.stdout)
        self.assertEqual(initial["reason"], "rollout_budget_exhausted")
        self.assertTrue(initial["closeout_eligible"])
        self.assertNotEqual(initial["candidate_tree"], initial["output_candidate_tree"])
        first = self.root / "slice-one.md"
        second = self.root / "slice-two.md"
        first.write_text("Scope: finish the first approved correction.\n")
        second.write_text("Scope: run the second approved correction.\n")
        result = self.cli("recover", initial["id"], first, second,
                          "--expected-tree", initial["output_candidate_tree"])
        self.assertEqual(result.returncode, 0, result.stderr)
        final = json.loads(result.stdout)
        middle = self.store.load(final["parent"])
        self.assertEqual(middle["kind"], "recover")
        self.assertEqual(middle["parent"], initial["id"])
        self.assertIn("first approved correction", (self.store.path(middle["id"]) / "prompt.txt").read_text())
        self.assertIn("second approved correction", (self.store.path(final["id"]) / "prompt.txt").read_text())
        self.assertNotEqual(self.cli("recover", initial["id"], first,
                                     "--expected-tree", initial["output_candidate_tree"]).returncode, 0)
        self.assertNotEqual(self.cli("recover", middle["id"], first,
                                     "--expected-tree", middle["output_candidate_tree"]).returncode, 0)
        failed = json.loads(self.cli("execute", self.plan(), self.repo,
                                     env={"FAKE_MODE": "budget"}).stdout)
        stopped = self.cli("recover", failed["id"], first, second,
                           "--expected-tree", failed["output_candidate_tree"],
                           env={"FAKE_MODE": "budget"})
        self.assertEqual(stopped.returncode, 1, stopped.stderr)
        self.assertEqual(json.loads(stopped.stdout)["outcome"], "INCONCLUSIVE")
        self.assertEqual(len([x for x in self.store.executions.iterdir()
                              if self.store.load(x.name).get("parent") == failed["id"]]), 1)

    def test_revision_bound_and_checkpoint_next(self):
        initial = json.loads(self.cli("execute", self.plan(), self.repo,
                                      env={"FAKE_CAPTURE": "change.txt"}, check=True).stdout)
        findings = self.root / "findings.md"
        findings.write_text("Finding: specific observed review defect.\n")
        first = json.loads(self.cli("revise", initial["id"], findings,
                                    "--expected-tree", initial["output_candidate_tree"], check=True).stdout)
        second = json.loads(self.cli("revise", first["id"], findings,
                                     "--expected-tree", first["output_candidate_tree"], check=True).stdout)
        self.assertNotEqual(self.cli("revise", second["id"], findings,
                                     "--expected-tree", second["output_candidate_tree"]).returncode, 0)
        point = json.loads(self.cli("checkpoint", second["worktree"],
                                    second["output_candidate_tree"], "--message", "feat: reviewed",
                                    check=True).stdout)["checkpoint_oid"]
        next_run = self.cli("next", second["id"], point, self.plan())
        self.assertEqual(next_run.returncode, 0, next_run.stderr)
        successor = json.loads(next_run.stdout)
        self.assertNotEqual(successor["worktree"], second["worktree"])
        self.assertTrue(Path(second["worktree"]).is_dir())
        self.assertEqual(successor["base_head"], point)
        self.assertEqual(json.loads(self.cli("candidate", successor["worktree"], check=True).stdout)["tree"],
                         successor["output_candidate_tree"])
        self.assertNotEqual(self.cli("next", second["id"], point, self.plan()).returncode, 0)

    def test_review_rejects_postrun_drift(self):
        worktree = self.worktree()
        tree = candidate(worktree)[1]
        result = self.cli("review", "correctness", worktree.path, tree, self.plan(),
                          env={"FAKE_MODE": "review", "FAKE_CAPTURE": "concurrent-change.txt"})
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(result.stdout)
        self.assertEqual(record["reason"], "postrun_candidate_drift")
        self.assertNotEqual(record["output_candidate_tree"], tree)
        self.assertEqual(record["report"]["verdict"], "APPROVE")
        self.assertEqual(json.loads((self.store.path(record["id"]) / "metrics.json").read_text())
                         ["classified_outcome"], "APPROVE")

    def test_timeout_and_cancel_kill_surviving_child(self):
        script = self.root / "parent.py"
        pid_file = self.root / "child.pid"
        script.write_text("import os,signal,subprocess,sys,time\n"
                          "child=subprocess.Popen([sys.executable,'-c',"
                          "'import signal,time;signal.signal(signal.SIGINT,signal.SIG_IGN);time.sleep(30)'],"
                          "stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)\n"
                          "open(sys.argv[1],'w').write(str(child.pid))\n"
                          "signal.signal(signal.SIGINT,lambda *_:sys.exit(130))\n"
                          "time.sleep(30)\n")
        for cancel in (False, True):
            pid_file.unlink(missing_ok=True)
            timer = threading.Timer(0.4, lambda: os.kill(os.getpid(), signal.SIGTERM)) if cancel else None
            if timer:
                timer.start()
            try:
                process = run_process([sys.executable, str(script), str(pid_file)],
                                      cwd=self.repo, env=self.env, deadline=2 if cancel else 0.4)
            finally:
                if timer:
                    timer.cancel()
                    timer.join()
            self.assertEqual(process.reason, "caller_signal" if cancel else "absolute_timeout")
            pid = int(pid_file.read_text())
            for _ in range(20):
                stat_path = Path(f"/proc/{pid}/stat")
                if not stat_path.exists() or stat_path.read_text().split()[2] == "Z":
                    break
                time.sleep(0.05)
            else:
                os.kill(pid, signal.SIGKILL)
                self.fail("descendant survived cancellation")

    def test_cli_cancel_kills_nested_codex_group(self):
        codex_pid = self.root / "codex.pid"
        child_pid = self.root / "child.pid"
        values = dict(self.env, FAKE_MODE="nested_ignore", FAKE_CODEX_PID=str(codex_pid),
                      FAKE_CHILD_PID=str(child_pid))
        command = [sys.executable, "-B", str(CLI), "execute", str(self.plan(launcher=[
            "sh", "-c", "printf launcher_cancel_marker >&2; exec \"$@\"", "sh"])), str(self.repo)]
        process = subprocess.Popen(command, env=values, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                if codex_pid.exists() and child_pid.exists():
                    break
                time.sleep(0.05)
            self.assertTrue(codex_pid.exists() and child_pid.exists(), "Codex fixture did not start")
            os.kill(process.pid, signal.SIGTERM)
            stdout, stderr = process.communicate(timeout=12)
            self.assertEqual(process.returncode, 1, stderr)
            record = json.loads(stdout)
            self.assertEqual((record["phase"], record["outcome"], record["reason"]),
                             ("finished", "INCONCLUSIVE", "caller_signal"))
            self.assertIn('"thread_id": "partial-evidence"',
                          Path(record["artifacts"]["events"]).read_text())
            self.assertIn("partial-diagnostic",
                          Path(record["artifacts"]["diagnostics"]).read_text())
            self.assertEqual(Path(record["artifacts"]["launcher_diagnostics"]).read_bytes(),
                             b"launcher_cancel_marker")
            for path in (codex_pid, child_pid):
                pid = int(path.read_text())
                stat_path = Path(f"/proc/{pid}/stat")
                if stat_path.exists():
                    self.assertEqual(stat_path.read_text().split()[2], "Z", f"surviving fixture PID {pid}")
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
            for path in (codex_pid, child_pid):
                if path.exists():
                    pid = int(path.read_text())
                    try:
                        os.kill(pid, signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_worker_deadline_preserves_partial_codex_evidence(self):
        worktree = self.worktree("deadline")
        plan = self.plan().read_bytes()
        roles_path = self.root / "roles.json"
        roles = json.loads((SKILL_ROOT / "config/roles.json").read_text())
        roles["standard"]["initialTimeout"] = 2
        roles_path.write_text(json.dumps(roles))
        record = CLI_FUNCTIONS["_record"](
            self.store, role="standard", worktree=worktree.path, common_dir=worktree.common_dir,
            branch=worktree.branch, head=worktree.head, tree=candidate(worktree)[1],
            grants=[], kind="execute")
        record["environment_settings"] = parse_plan(plan)
        record["role_settings"] = read_roles(roles_path)["standard"]
        self.store.create(record, plan, b"assigned prompt")
        codex_pid = self.root / "deadline-codex.pid"
        child_pid = self.root / "deadline-child.pid"
        values = dict(self.env, FAKE_MODE="nested_ignore", FAKE_CODEX_PID=str(codex_pid),
                      FAKE_CHILD_PID=str(child_pid))
        try:
            with patch.dict(CLI_FUNCTIONS["_verify_snapshot"].__globals__, {"ROLES": roles_path}), \
                 patch.dict(run_process.__globals__, {"KILL_GRACE_SECONDS": 0.2}), \
                 patch.dict(os.environ, values):
                finished = CLI_FUNCTIONS["_worker"](self.store, record["id"])
            self.assertEqual((finished["phase"], finished["outcome"], finished["reason"]),
                             ("finished", "INCONCLUSIVE", "absolute_timeout"))
            self.assertIn('"thread_id": "partial-evidence"',
                          Path(finished["artifacts"]["events"]).read_text())
            self.assertIn("partial-diagnostic",
                          Path(finished["artifacts"]["diagnostics"]).read_text())
            for path in (codex_pid, child_pid):
                self.assertTrue(path.exists(), "Codex fixture did not start")
                pid = int(path.read_text())
                stat_path = Path(f"/proc/{pid}/stat")
                if stat_path.exists():
                    self.assertEqual(stat_path.read_text().split()[2], "Z", f"surviving fixture PID {pid}")
        finally:
            for path in (codex_pid, child_pid):
                if path.exists():
                    try:
                        os.kill(int(path.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_worker_death_preserves_codex_evidence_and_stops_group(self):
        worker_pid = self.root / "worker.pid"
        codex_pid = self.root / "codex.pid"
        child_pid = self.root / "child.pid"
        values = dict(self.env, FAKE_MODE="nested_ignore", FAKE_WORKER_PID=str(worker_pid),
                      FAKE_CODEX_PID=str(codex_pid), FAKE_CHILD_PID=str(child_pid))
        command = [sys.executable, "-B", str(CLI), "execute", str(self.plan()), str(self.repo)]
        process = subprocess.Popen(command, env=values, text=True, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE)
        try:
            for _ in range(100):
                locations = list(self.store.executions.iterdir())
                if (worker_pid.exists() and codex_pid.exists() and child_pid.exists() and
                    locations and b"partial-evidence" in (locations[0] / "events.jsonl").read_bytes() and
                    b"partial-diagnostic" in (locations[0] / "diagnostics.txt").read_bytes()):
                    break
                time.sleep(0.05)
            else:
                self.fail("Codex evidence did not arrive before worker death")
            os.kill(int(worker_pid.read_text()), signal.SIGKILL)
            stdout, stderr = process.communicate(timeout=12)
            self.assertEqual(process.returncode, 1, stderr)
            record = json.loads(stdout)
            self.assertEqual((record["outcome"], record["reason"]),
                             ("INCONCLUSIVE", "launcher_exit_-9"))
            self.assertIn("partial-evidence", Path(record["artifacts"]["events"]).read_text())
            self.assertIn("partial-diagnostic", Path(record["artifacts"]["diagnostics"]).read_text())
            for path in (codex_pid, child_pid):
                pid = int(path.read_text())
                for _ in range(20):
                    stat_path = Path(f"/proc/{pid}/stat")
                    if not stat_path.exists() or stat_path.read_text().split()[2] == "Z":
                        break
                    time.sleep(0.05)
                else:
                    self.fail(f"surviving fixture PID {pid}")
        finally:
            if process.poll() is None:
                process.kill()
                process.communicate()
            for path in (codex_pid, child_pid):
                if path.exists():
                    try:
                        os.kill(int(path.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass

    def test_grant_is_explicit_native_permission(self):
        capture = self.root / "command.json"
        result = self.cli("execute", self.plan(), self.repo, "--grant", ".agents",
                          env={"FAKE_CAPTURE": str(capture)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["outcome"], "COMPLETE")
        command = " ".join(json.loads(capture.read_text()))
        self.assertIn('".agents" = "write"', command)
        self.assertIn('".codex" = "read"', command)
        self.assertIn('".git" = "read"', command)


if __name__ == "__main__":
    unittest.main()

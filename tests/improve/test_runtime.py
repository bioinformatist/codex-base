"""Focused .18 runtime fixtures: real Git/Worktrunk and fake native Codex."""

from __future__ import annotations

import json
import io
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
from types import SimpleNamespace
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
SKILL_ROOT = Path(os.environ.get("CODEX_IMPROVE_SKILL_ROOT", ROOT / "src/improve"))
RUNTIME = SKILL_ROOT / "runtime"
CLI = SKILL_ROOT / "scripts/codex-improve"
sys.path.insert(0, str(RUNTIME))

from contracts import StateStore, digest, parse_plan, read_roles
from git_worktree import (BoundaryError, candidate, check_write_paths, checkpoint, copy_ignored,
                          create_worktree, git, integrate_exact, require_candidate,
                          require_oid, validate_worktree, wt)
from transport import ProcessResult, classify, codex_command, run_process
from visual import decode, import_images, image_paths, validate_visual

with patch.dict(os.environ):
    os.environ.pop("CODEX_IMPROVE_CODEX", None)
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
        self.env.pop("CODEX_IMPROVE_CODEX", None)
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
    report = {'verdict':'APPROVE','summary':'Checked','findings':[],
      'coverage':[{'check':'scope','status':'PASS','evidence':'fixture'}],
      'review_blockers':[],'deferred_acceptance':[]}
    if os.environ.get('FAKE_REVIEW_REPORT'):
        report = json.loads(os.environ['FAKE_REVIEW_REPORT'])
    final.write_text(json.dumps(report))
elif mode == 'visual':
    ids = [pathlib.Path(args[i+1]).name for i, arg in enumerate(args) if arg == '--image']
    final.write_text(json.dumps({'status':'COMPLETE','inputIds':ids,'observations':[
      {'inputId':i,'location':'whole frame','observation':'Unique observation: a red rectangle',
       'inference':'none','comparison':'none','uncertainty':'none'} for i in ids],
      'unchecked':[],'stoppedBecause':None}))
else:
    final.write_text(json.dumps({'status':'COMPLETE','steps':['done'],
      'stoppedBecause':None,'filesChanged':[],'notes':[]}))
""")
        fake.chmod(0o755)
        self.env["PATH"] = str(self.bin) + os.pathsep + self.env["PATH"]

    def worktree(self, name="fixture"):
        return create_worktree(self.repo, f"codex/improve-{name}", self.base, self.store.worktrees)

    def review_execution(self, worktree, **plan_options):
        worktree = validate_worktree(worktree)
        plan = self.plan(**plan_options).read_bytes()
        record = CLI_FUNCTIONS["_record"](self.store, role="standard", worktree=worktree.path,
            common_dir=worktree.common_dir,branch=worktree.branch,head=worktree.head,
            tree=candidate(worktree)[1],grants=[],kind="execute")
        with patch.dict(CLI_FUNCTIONS["start"].__globals__, {"launch": lambda _store, item: item}):
            record = CLI_FUNCTIONS["start"](self.store, record, plan, b"fixture execution")
        record.update(output_head=worktree.head,output_candidate_tree=record["candidate_tree"],
                      phase="finished",outcome="COMPLETE")
        self.store.save(record)
        return record

    def visual_execution(self, worktree):
        from PIL import Image
        Image.new("RGB", (12, 8), "red").save(self.root / "image.png")
        manifest = self.root / "inputs.json"
        manifest.write_text(json.dumps({"version":1,"images":[{
            "path":"image.png","purpose":"reference","source":"synthetic fixture"}]}))
        return json.loads(self.cli("visual", worktree.path, candidate(worktree)[1],
            self.plan(lane="visual", paths=[]), "--inputs", manifest,
            env={"FAKE_MODE":"visual"}, check=True).stdout)

    def revise_report(self):
        return {"verdict":"REVISE","summary":"One issue", "findings":[{
            "check":"scope","severity":"medium","location":"tracked.txt:1","claim":"Wrong result",
            "evidence":"fixture","action":"Fix result"}],
            "coverage":[{"check":"scope","status":"FAIL","evidence":"One issue"}],
            "review_blockers":[],"deferred_acceptance":[]}

    def review_dossier(self, record, evidence=None):
        path=self.root/("review-"+record["id"]+".json")
        path.write_text(json.dumps({"version":1,"executionId":record["id"],"head":record["output_head"],
            "tree":record["output_candidate_tree"],"evidence":evidence or [],"notes":"inspect complete scope"}))
        return path

    def cli(self, *args, env=None, check=False):
        values = dict(self.env)
        if env:
            values.update(env)
        result = run(sys.executable, "-B", CLI, *args, env=values, check=False)
        if check and result.returncode:
            record = json.loads(result.stdout) if result.stdout else {}
            diagnostics = (Path(record["artifacts"]["diagnostics"]).read_text()
                           if record.get("artifacts") else "")
            self.fail(f"CLI failed: {result.stdout}\n{result.stderr}\n{diagnostics}")
        return result

    def plan(self, probes=None, contract="1.0.0-codex.18", launcher=None, lane="standard",
             paths=None, inputs=None, gates=None):
        plan = self.root / "plan.md"
        plan.write_text(f"- **Improve contract**: `{contract}`\n"
                        "```json codex-improve-environment\n" +
                        json.dumps({"version": 1, "launcher": launcher or ["env"], "probes": probes or []}) +
                        "\n```\n```json codex-improve-routing\n" +
                        json.dumps({"version":1,"lane":lane,"writePaths": ["*"] if paths is None else paths,
                                    "requiredEvidence":[gate["id"] for gate in (gates or []) if gate["class"] == "implementation gate"],
                                    "inputs":inputs or {}}) +
                        "\n```\n```json codex-improve-gates\n" +
                        json.dumps({"version":1,"gates":gates or []}) + "\n```\n")
        return plan


class GitAndWorktrunk(Fixture):
    def test_scope_covers_rename_deletion_and_mode_and_protected_paths(self):
        worktree = self.worktree()
        base = candidate(worktree)[1]
        (worktree.path / "tracked.txt").rename(worktree.path / "renamed.txt")
        tree = candidate(worktree)[1]
        with self.assertRaisesRegex(BoundaryError, "outside authenticated"):
            check_write_paths(worktree, base, tree, ["renamed.txt"], [])
        check_write_paths(worktree, base, tree, ["tracked.txt", "renamed.txt"], [])
        (worktree.path / "renamed.txt").rename(worktree.path / "tracked.txt")
        (worktree.path / "tracked.txt").chmod(0o755)
        tree = candidate(worktree)[1]
        with self.assertRaises(BoundaryError):
            check_write_paths(worktree, base, tree, ["other.txt"], [])
        (worktree.path / ".agents").mkdir()
        (worktree.path / ".agents/x").write_text("protected")
        tree = candidate(worktree)[1]
        with self.assertRaises(BoundaryError):
            check_write_paths(worktree, base, tree, ["*"], [])
        check_write_paths(worktree, base, tree, ["*"], [".agents"])

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
                rejected = self.cli("checkpoint", record["id"], tree, "--message", "feat: blocked")
                self.assertEqual(rejected.returncode, 2)
                self.assertIn("writable execution", rejected.stderr)
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
    def test_latest_review_invalidates_approval(self):
        blocked = self.revise_report()
        blocked.update(verdict="BLOCK", review_blockers=[{"item":"Missing context","impact":"Cannot finish"}])
        blocked["coverage"][0]["status"] = "BLOCKED"
        for outcome, env in (("REVISE", {"FAKE_MODE":"review", "FAKE_REVIEW_REPORT":json.dumps(self.revise_report())}),
                             ("BLOCK", {"FAKE_MODE":"review", "FAKE_REVIEW_REPORT":json.dumps(blocked)}),
                             ("INCONCLUSIVE", {"FAKE_MODE":"budget"})):
            with self.subTest(outcome=outcome):
                worktree = self.worktree(outcome)
                (worktree.path / "tracked.txt").write_text("changed\n")
                execution = self.review_execution(worktree.path)
                dossier = self.review_dossier(execution)
                first = json.loads(self.cli("review", execution["id"], execution["output_candidate_tree"],
                    dossier, env={"FAKE_MODE":"review"}, check=True).stdout)
                cached = json.loads(self.cli("review", execution["id"], execution["output_candidate_tree"],
                    dossier, env={"FAKE_MODE":"budget"}, check=True).stdout)
                self.assertEqual(cached["id"], first["id"])
                data = json.loads(dossier.read_text())
                data["notes"] = "New inspection found a defect"
                dossier.write_text(json.dumps(data))
                result = self.cli("review", execution["id"], execution["output_candidate_tree"], dossier, env=env)
                self.assertEqual(result.returncode, 1 if outcome == "INCONCLUSIVE" else 0, result.stderr)
                latest = json.loads(result.stdout)
                self.assertEqual((first["outcome"], latest["outcome"], latest["parent"]),
                                 ("APPROVE", outcome, first["id"]))
                self.assertNotIn("approval", self.store.load(execution["id"]))
                rejected = self.cli("checkpoint", execution["id"], execution["output_candidate_tree"],
                                    "--message", "test: obsolete approval")
                self.assertEqual(rejected.returncode, 2, rejected.stdout)
                self.assertIn("approval", rejected.stderr)

    def test_review_binds_current_reviewer_settings(self):
        worktree = self.worktree()
        (worktree.path / "tracked.txt").write_text("changed\n")
        execution = self.review_execution(worktree.path)
        dossier = self.review_dossier(execution)
        first = json.loads(self.cli("review", execution["id"], execution["output_candidate_tree"],
            dossier, env={"FAKE_MODE":"review"}, check=True).stdout)
        roles = read_roles(SKILL_ROOT / "config/roles.json")
        roles["reviewer"]["reasoningEffort"] = "medium"
        private_roles = self.root / "roles.json"
        private_roles.write_text(json.dumps(roles))
        cmd = CLI_FUNCTIONS["cmd_review"]
        args = SimpleNamespace(execution_id=execution["id"], tree=execution["output_candidate_tree"],
                               dossier=dossier, retry_of=None, retry_authorized=False)
        with patch.dict(cmd.__globals__, {"ROLES":private_roles,
                "launch": lambda store, record: CLI_FUNCTIONS["_worker"](store, record["id"])}), \
             patch.dict(os.environ, self.env):
            with self.assertRaisesRegex(BoundaryError, "stale"):
                CLI_FUNCTIONS["cmd_checkpoint"](SimpleNamespace(
                    execution_id=execution["id"], tree=args.tree, message="test: stale settings",
                    integrate_oid=None, target=None, expected_target=None), self.store)
            with patch.dict(os.environ, {"FAKE_MODE":"review"}):
                second = cmd(args, self.store)
        self.assertNotEqual(second["id"], first["id"])
        self.assertEqual(second["outcome"], "APPROVE")
        self.assertEqual(second["role_settings"], roles["reviewer"])
        self.assertEqual(second["review_binding"]["reviewer"], roles["reviewer"])

    def test_review_resume_preserves_execution_and_visual_context(self):
        worktree = self.worktree()
        visual = self.visual_execution(worktree)
        probe = self.root / "review-probe.py"
        probe.write_text("raise SystemExit(1)\n")
        execution = self.review_execution(worktree.path,
            probes=[{"argv":[sys.executable,str(probe)],"timeoutSeconds":2}],
            inputs={"visual":{"executionId":visual["id"],
                              "inputIds":visual["report"]["inputIds"],"report":True}})
        first = json.loads(self.cli("review", execution["id"], execution["output_candidate_tree"],
            self.review_dossier(execution), env={"FAKE_MODE":"review"}, check=True).stdout)
        self.assertEqual(first["reason"], "environment_preflight_failed")
        prompt = (self.store.path(first["id"]) / "prompt.txt").read_bytes()
        self.assertIn(b"Original image inputs", prompt)
        self.assertIn(b"Unique observation: a red rectangle", prompt)
        probe.write_text("pass\n")
        capture = self.root / "review-command.json"
        resumed = json.loads(self.cli("resume", first["id"],
            env={"FAKE_MODE":"review","FAKE_CAPTURE":str(capture)}, check=True).stdout)
        self.assertEqual(resumed["outcome"], "APPROVE")
        self.assertEqual((resumed["parent"], resumed["attempt"], resumed["lineage"], resumed["resume_used"]),
                         (first["id"], first["attempt"] + 1, execution["lineage"], True))
        for key in ("execution_id", "review_binding", "images", "image_owner", "visual_report", "role_settings"):
            self.assertEqual(resumed[key], first[key], key)
        self.assertEqual((self.store.path(resumed["id"]) / "prompt.txt").read_bytes(), prompt)
        self.assertEqual((self.store.path(resumed["id"]) / "dossier.json").read_bytes(),
                         (self.store.path(first["id"]) / "dossier.json").read_bytes())
        self.assertEqual(self.store.load(execution["id"])["approval"]["reviewId"], resumed["id"])
        self.assertEqual(self.store.load(execution["lineage"])["last_review"], resumed["id"])
        argv = json.loads(capture.read_text())
        self.assertEqual([Path(argv[i+1]) for i, arg in enumerate(argv) if arg == "--image"],
                         image_paths(self.store, execution))
        self.assertIn("read-only", argv)
        self.assertEqual(self.cli("resume", first["id"]).returncode, 2)

    def test_reconciliation_disposes_findings_without_rewriting_review(self):
        worktree = self.worktree()
        (worktree.path / "tracked.txt").write_text("changed\n")
        execution = self.review_execution(worktree.path)
        review = json.loads(self.cli("review", execution["id"], execution["output_candidate_tree"],
            self.review_dossier(execution), env={"FAKE_MODE":"review",
            "FAKE_REVIEW_REPORT":json.dumps(self.revise_report())}, check=True).stdout)
        original = Path(review["artifacts"]["final"]).read_bytes()
        artifact = self.root / "reproducer.txt"
        artifact.write_text("Observed behavior disproves the finding.\n")
        support = {"path":str(artifact),"sha256":digest(artifact.read_bytes())}
        data = {"version":1,"conclusion":"APPROVE","findings":[{
            "index":0,"disposition":"unresolved","evidence":[support],"conclusion":"Reproducer checked"}],
            "evidence":[support],"reason":"All findings have supporting evidence"}
        dossier = self.root / "reconcile.json"
        for disposition, supports in (("unresolved", [support]), ("rejected", [])):
            data["findings"][0].update(disposition=disposition, evidence=supports)
            dossier.write_text(json.dumps(data))
            self.assertEqual(self.cli("reconcile", review["id"], dossier).returncode, 2)
        data["findings"][0]["evidence"] = [support]
        dossier.write_text(json.dumps(data))
        reconciled = json.loads(self.cli("reconcile", review["id"], dossier, check=True).stdout)
        self.assertEqual(reconciled["report"], review["report"])
        self.assertEqual(reconciled["outcome"], "REVISE")
        self.assertEqual(Path(review["artifacts"]["final"]).read_bytes(), original)
        self.assertEqual(self.store.load(execution["id"])["approval"]["source"], "reconciliation")
        original_support = artifact.read_bytes()
        artifact.write_text("Changed supporting evidence\n")
        for args in (("review", execution["id"], execution["output_candidate_tree"], self.review_dossier(execution)),
                     ("checkpoint", execution["id"], execution["output_candidate_tree"], "--message", "test: stale support")):
            stale = self.cli(*args, env={"FAKE_MODE":"budget"})
            self.assertEqual(stale.returncode, 2)
            self.assertIn("reconciliation evidence digest mismatch", stale.stderr)
        artifact.write_bytes(original_support)
        cached = json.loads(self.cli("review", execution["id"], execution["output_candidate_tree"],
            self.review_dossier(execution), env={"FAKE_MODE":"budget"}, check=True).stdout)
        self.assertEqual(cached["id"], review["id"])
        self.cli("checkpoint", execution["id"], execution["output_candidate_tree"],
                 "--message", "test: reconciled candidate", check=True)

    def test_review_rejects_missing_conflicting_and_stale_gate_evidence(self):
        worktree = self.worktree()
        (worktree.path / "tracked.txt").write_text("changed\n")
        gate = {"id":"G1","class":"implementation gate","kind":"check","check":"focused check",
                "invalidatedBy":["always-invalidated"],"environment":"fixture","conditions":"required"}
        execution = self.review_execution(worktree.path, gates=[gate])
        tree = execution["output_candidate_tree"]
        rejected = self.cli("checkpoint", execution["id"], tree, "--message", "test: unapproved")
        self.assertEqual(rejected.returncode, 2)
        self.assertIn("approval", rejected.stderr)
        artifact = self.root / "gate.txt"
        artifact.write_text("Focused check passed\n")
        entry = {"gate":"G1","status":"PASS","artifact":{"path":str(artifact),"sha256":digest(artifact.read_bytes())},
                 "environment":"fixture","head":execution["output_head"],"tree":tree,"planHash":execution["plan_hash"]}
        dossier = self.review_dossier(execution, [entry])
        valid = json.loads(dossier.read_text())
        invalid = [{**valid, "executionId":"0" * 32}, {**valid, "evidence":[]},
                   {**valid, "evidence":[entry, entry]}]
        invalid.extend({**valid, "evidence":[{**entry, **change}]} for change in (
            {"gate":"UNKNOWN"}, {"status":"PENDING"}, {"status":"FAIL"}, {"tree":"0" * 40},
            {"planHash":"stale"}, {"environment":"other"},
            {"artifact":{"path":str(artifact),"sha256":"stale"}}))
        capture = self.root / "unexpected-model.json"
        for data in invalid:
            with self.subTest(dossier=data):
                dossier.write_text(json.dumps(data))
                result = self.cli("review", execution["id"], tree, dossier, env={"FAKE_CAPTURE":str(capture)})
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertFalse(capture.exists())
        dossier.write_text(json.dumps(valid))
        report = {"verdict":"APPROVE","summary":"Checked", "findings":[], "review_blockers":[],
                  "coverage":[{"check":check,"status":"PASS","evidence":"checked"} for check in ("scope","G1")],
                  "deferred_acceptance":[]}
        self.cli("review", execution["id"], tree, dossier,
                 env={"FAKE_MODE":"review","FAKE_REVIEW_REPORT":json.dumps(report)}, check=True)
        artifact.write_text("Changed evidence\n")
        stale = self.cli("checkpoint", execution["id"], tree, "--message", "test: stale evidence")
        self.assertEqual(stale.returncode, 2)
        self.assertIn("digest mismatch", stale.stderr)

    def test_reconciliation_keeps_unrelated_failures_blockers_and_required_gates(self):
        worktree = self.worktree()
        gate = {"id":"G1","class":"implementation gate","kind":"check","check":"focused check",
                "invalidatedBy":["always-invalidated"],"environment":"fixture","conditions":"required"}
        execution = self.review_execution(worktree.path, gates=[gate])
        artifact = self.root / "support.txt"
        artifact.write_text("Focused check passed; finding disproved by reproducer\n")
        support = {"path":str(artifact),"sha256":digest(artifact.read_bytes())}
        entry = {"gate":"G1","status":"PASS","artifact":support,"environment":"fixture",
                 "head":execution["output_head"],"tree":execution["output_candidate_tree"],"planHash":execution["plan_hash"]}
        dossier = self.review_dossier(execution, [entry])
        disposition = self.root / "disposition.json"
        disposition.write_text(json.dumps({"version":1,"conclusion":"APPROVE","findings":[{
            "index":0,"disposition":"rejected","evidence":[support],"conclusion":"Reproducer disproves finding"}],
            "evidence":[support],"reason":"All findings disposed"}))
        for kind in ("unrelated failure", "unchecked scope", "blocker", "stale required gate"):
            with self.subTest(kind=kind):
                report = self.revise_report()
                report["coverage"].append({"check":"G1","status":"PASS","evidence":"focused check"})
                if kind == "unrelated failure":
                    report["coverage"][1]["status"] = "FAIL"
                elif kind == "unchecked scope":
                    report["findings"][0]["check"] = "G1"
                    report["coverage"][0]["status"] = "BLOCKED"
                    report["coverage"][1]["status"] = "FAIL"
                    report["verdict"] = "BLOCK"
                elif kind == "blocker":
                    report.update(verdict="BLOCK", review_blockers=[{"item":"Missing context","impact":"Unchecked behavior"}])
                review = json.loads(self.cli("review", execution["id"], execution["output_candidate_tree"], dossier,
                    env={"FAKE_MODE":"review","FAKE_REVIEW_REPORT":json.dumps(report)}, check=True).stdout)
                original = Path(review["artifacts"]["final"]).read_bytes()
                if kind == "stale required gate":
                    artifact.write_text("Evidence changed after review\n")
                    # Keep the disposition supported so the original required gate is what rejects it.
                    data = json.loads(disposition.read_text())
                    current = {"path":str(artifact),"sha256":digest(artifact.read_bytes())}
                    data["evidence"] = data["findings"][0]["evidence"] = [current]
                    disposition.write_text(json.dumps(data))
                result = self.cli("reconcile", review["id"], disposition)
                self.assertEqual(result.returncode, 2, result.stdout)
                self.assertIn("digest mismatch" if kind == "stale required gate" else "contradicts findings", result.stderr)
                self.assertNotIn("approval", self.store.load(execution["id"]))
                self.assertEqual(Path(review["artifacts"]["final"]).read_bytes(), original)

    def test_review_retry_authorization_stays_with_execution_lineage(self):
        worktree = self.worktree()
        execution = self.review_execution(worktree.path)
        failed = self.cli("review", execution["id"], execution["output_candidate_tree"],
                          self.review_dossier(execution), env={"FAKE_MODE":"budget"})
        self.assertEqual(failed.returncode, 1, failed.stderr)
        review = json.loads(failed.stdout)
        findings = self.root / "findings.md"
        findings.write_text("Finding: finish the approved correction.\n")
        revised = json.loads(self.cli("revise", execution["id"], findings,
            "--expected-tree", execution["output_candidate_tree"], check=True).stdout)
        dossier = self.review_dossier(revised)
        for retry in ([], ["--retry-of", "0" * 32, "--retry-authorized"], ["--retry-of", review["id"]]):
            result = self.cli("review", revised["id"], revised["output_candidate_tree"], dossier, *retry)
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn("INCONCLUSIVE", result.stderr)
        current = json.loads(self.cli("review", revised["id"], revised["output_candidate_tree"], dossier,
            "--retry-of", review["id"], "--retry-authorized", env={"FAKE_MODE":"review"}, check=True).stdout)
        self.assertEqual((current["parent"], current["attempt"], current["lineage"], current["execution_id"]),
                         (review["id"], review["attempt"] + 1, execution["lineage"], revised["id"]))
        self.assertEqual(self.store.load(review["id"])["outcome"], "INCONCLUSIVE")

    def test_images_validate_snapshot_limits_paths_and_report_ids(self):
        from PIL import Image
        output = io.BytesIO()
        Image.new("RGB", (12, 8), "red").save(output, format="PNG")
        raw = output.getvalue()
        image = self.root / "image.png"
        image.write_bytes(raw)
        manifest = self.root / "inputs.json"
        entry = {"path":"image.png", "purpose":"reference", "source":"synthetic fixture"}
        manifest.write_text(json.dumps({"version":1, "images":[entry]}))
        plan = self.plan().read_bytes()
        record = CLI_FUNCTIONS["_record"](self.store, role="visual", worktree=self.repo,
            common_dir=self.repo / ".git", branch="main", head=self.base,
            tree=git(self.repo,"rev-parse","HEAD^{tree}"), grants=[], kind="visual")
        record["plan_settings"] = parse_plan(plan)
        self.store.create(record, plan, b"visual test")
        import_images(self.store, record, manifest)
        paths = image_paths(self.store, record)
        self.assertEqual(paths[0].read_bytes(), raw)
        self.assertEqual(stat.S_IMODE(paths[0].stat().st_mode), 0o400)
        image_id = record["images"][0]["id"]
        report = {"status":"COMPLETE", "inputIds":[image_id], "observations":[{
            "inputId":image_id,"location":"whole frame","observation":"red rectangle",
            "inference":"none","comparison":"none","uncertainty":"none"}],
            "unchecked":[],"stoppedBecause":None}
        validate_visual(report, record["images"])
        report["observations"][0]["inputId"] = "unknown"
        with self.assertRaises(BoundaryError):
            validate_visual(report, record["images"])
        paths[0].chmod(0o600)
        paths[0].write_bytes(b"tampered")
        with self.assertRaises(BoundaryError):
            image_paths(self.store, record)
        for name in ("../image.png", "missing.png", "link.png"):
            (self.root / "link.png").unlink(missing_ok=True)
            (self.root / "link.png").symlink_to(image)
            entry["path"] = name
            manifest.write_text(json.dumps({"version":1,"images":[entry]}))
            with self.assertRaises(BoundaryError):
                import_images(self.store, record, manifest)
        with self.assertRaises(BoundaryError):
            decode(b"\x89PNG\r\n\x1a\nnot an image")
        record["plan_settings"]["routing"]["inputs"]["imageLimits"] = {
            "count":1,"perImageBytes":1,"totalBytes":1}
        entry["path"] = "image.png"
        manifest.write_text(json.dumps({"version":1,"images":[entry]}))
        with self.assertRaises(BoundaryError):
            import_images(self.store, record, manifest)
        record["plan_settings"]["routing"]["inputs"].pop("imageLimits")
        entry["capture"] = {"tree":record["candidate_tree"]}
        entry["purpose"] = "candidate"
        manifest.write_text(json.dumps({"version":1,"images":[entry]}))
        with self.assertRaises(BoundaryError):
            import_images(self.store, record, manifest)

    def test_writer_scope_violation_preserves_output_and_stops_followup(self):
        plan = self.plan(paths=["tracked.txt"])
        result = self.cli("execute", plan, self.repo,
                          env={"FAKE_CAPTURE":"outside.txt"}, check=True)
        record = json.loads(result.stdout)
        self.assertEqual((record["outcome"], record["reason"]), ("STOPPED", "write_paths_violation"))
        self.assertTrue((Path(record["worktree"]) / "outside.txt").is_file())
        findings = self.root / "findings.md"
        findings.write_text("Finding: fix scope")
        self.assertEqual(self.cli("revise", record["id"], findings,
                                  "--expected-tree", record["output_candidate_tree"]).returncode, 2)

    def test_routing_roles_and_conflicts_fail_before_model(self):
        roles = read_roles(SKILL_ROOT / "config/roles.json")
        self.assertEqual(len(roles), 7)
        self.assertEqual((roles["visual"]["model"], roles["visual"]["reasoningEffort"]),
                         ("gpt-6.1-terra", "medium"))
        self.assertEqual((roles["writer"]["model"], roles["writer"]["reasoningEffort"]),
                         ("gpt-6.1-terra", "low"))
        self.assertFalse(roles["writer"]["networkAccess"])
        capture = self.root / "command.json"
        result = self.cli("execute", self.plan(lane="deep"), self.repo, "--lane", "standard",
                          env={"FAKE_CAPTURE": str(capture)})
        self.assertEqual(result.returncode, 2)
        self.assertIn("lane conflict", result.stderr)
        self.assertFalse(capture.exists())
        result = self.cli("execute", self.plan(lane="writer"), self.repo,
                          env={"FAKE_CAPTURE": str(capture)})
        self.assertEqual(result.returncode, 2)
        self.assertIn("settled materials", result.stderr)
        self.assertFalse(capture.exists())
        materials = {"facts":[{"fact":"A settled fact", "source":"tracked.txt:1"}],
                     "conclusions":["Use the fact"], "audience":"contributors", "language":"English",
                     "terminology":[], "preserve":["technical meaning"], "scope":["tracked.txt"],
                     "acceptance":["accurate prose"]}
        result = self.cli("execute", self.plan(lane="writer", inputs={"writer":materials}), self.repo,
                          env={"FAKE_CAPTURE":str(capture)}, check=True)
        self.assertEqual(json.loads(result.stdout)["role"], "writer")
        args = json.loads(capture.read_text())
        self.assertIn("permissions.improve-executor-runtime.network.enabled=false", args)
        self.assertIn("gpt-6.1-terra", args)
        with self.assertRaisesRegex(BoundaryError, "contract"):
            parse_plan(self.plan(contract="1.0.0-codex.17").read_bytes())

    def test_phase_methods_are_loaded_from_the_skill_layout(self):
        executor = CLI_FUNCTIONS["_executor_prompt"](b"approved plan", "a" * 40,
                                                       "standard", grants=[])
        review = CLI_FUNCTIONS["_review_prompt"](b"review dossier", "a" * 40)
        self.assertIn(b"## The smallest complete change", executor)
        self.assertNotIn(b"## 1. Understand first", executor)
        self.assertIn(b"## 1. Understand first", review)
        self.assertNotIn(b"## The smallest complete change", review)
        self.assertTrue(executor.endswith(b"approved plan"))
        self.assertTrue(review.endswith(b"review dossier"))
        loader = CLI_FUNCTIONS["_method_resource"]
        with patch.dict(loader.__globals__, {"SOURCE": self.root / "skills/improve"}):
            with self.assertRaisesRegex(BoundaryError, "missing Ponytail core resource"):
                loader("core")

    def test_selected_codex_survives_launcher_path_change(self):
        selected = self.root / "selected-codex"
        marker = self.root / "selected-called"
        selected.write_text(f"#!/bin/sh\nprintf selected > {marker}\nexec {self.bin / 'codex'} \"$@\"\n")
        selected.chmod(0o755)
        conflict_bin = self.root / "conflict-bin"
        conflict_bin.mkdir()
        conflict = conflict_bin / "codex"
        conflict.write_text(f"#!/bin/sh\nprintf conflict > {self.root / 'conflict-called'}\nexit 97\n")
        conflict.chmod(0o755)
        launcher = ["env", "PATH=" + str(conflict_bin) + os.pathsep + self.env["PATH"]]
        result = self.cli("execute", self.plan(launcher=launcher), self.repo,
                          env={"CODEX_IMPROVE_CODEX": str(selected)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["outcome"], "COMPLETE")
        self.assertEqual(marker.read_text(), "selected")
        self.assertFalse((self.root / "conflict-called").exists())

        selected.chmod(0o644)
        marker.unlink()
        failed = self.cli("execute", self.plan(launcher=launcher), self.repo,
                          env={"CODEX_IMPROVE_CODEX": str(selected)})
        self.assertEqual(failed.returncode, 2)
        self.assertIn(str(selected), failed.stderr)
        self.assertFalse(marker.exists())
        self.assertFalse((self.root / "conflict-called").exists())

        missing = self.root / "missing-codex"
        failed = self.cli("execute", self.plan(launcher=launcher), self.repo,
                          env={"CODEX_IMPROVE_CODEX": str(missing)})
        self.assertEqual(failed.returncode, 2)
        self.assertIn(str(missing), failed.stderr)
        self.assertFalse((self.root / "conflict-called").exists())

    def test_status_reports_live_and_finished_records(self):
        worktree = self.worktree()
        plan = self.plan().read_bytes()
        record = CLI_FUNCTIONS["_record"](
            self.store, role="standard", worktree=worktree.path, common_dir=worktree.common_dir,
            branch=worktree.branch, head=worktree.head, tree=candidate(worktree)[1],
            grants=[], kind="execute")
        record["plan_settings"] = parse_plan(plan)
        record["environment_settings"] = record["plan_settings"]["environment"]
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
        raw = b'- **Improve contract**: `1.0.0-codex.18`\n```json codex-improve-environment\n{"version":1,"version":1,"launcher":["env"],"probes":[]}\n```\n'
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
        # Dangling protected roots are refused before invoking a model.
        execution = self.review_execution(worktree.path)
        result = self.cli("review", execution["id"], candidate(worktree)[1], self.review_dossier(execution))
        self.assertEqual(result.returncode, 2, result.stderr)
        self.assertIn("protected root", result.stderr)
        (worktree.path / ".agents").unlink()
        execution = self.review_execution(worktree.path)
        capture = self.root / "command.json"
        result = self.cli("review", execution["id"], candidate(worktree)[1], self.review_dossier(execution),
                          env={"FAKE_MODE": "review", "FAKE_CAPTURE": str(capture)})
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(json.loads(result.stdout)["outcome"], "APPROVE")
        self.assertEqual(json.loads(result.stdout)["role"], "reviewer")
        args = json.loads(capture.read_text())
        self.assertEqual(args[args.index("--model") + 1], "gpt-6.1-sol")
        self.assertIn('model_reasoning_effort="high"', args)
        self.assertIn("read-only", args)
        self.assertNotIn("workspace-write", args)
        self.assertIn("--strict-config", args)

    def test_review_separates_deferred_ci_and_retains_validation_error(self):
        worktree = self.worktree()
        (worktree.path / "tracked.txt").write_text("changed\n")
        tree = candidate(worktree)[1]
        deferred_gate = {"id":"CI","class":"deferred acceptance","kind":"check","check":"CI",
                         "invalidatedBy":["always-invalidated"],"environment":"CI","conditions":"published"}
        execution = self.review_execution(worktree.path,gates=[deferred_gate])
        report = {
            "verdict": "APPROVE", "summary": "Implementation checked", "findings": [],
            "coverage": [{"check": "scope", "status": "PASS", "evidence": "inspected"}],
            "review_blockers": [],
            "deferred_acceptance": [{
                "check": "CI", "owner": "maintainer", "reason": "runs after publication",
                "evidence_required": "passing CI for the reviewed candidate",
            }],
        }

        def review():
            result = self.cli("review", execution["id"], tree, self.review_dossier(execution),
                              env={"FAKE_MODE": "review", "FAKE_REVIEW_REPORT": json.dumps(report)})
            return result, json.loads(result.stdout)

        result, record = review()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(record["outcome"], "APPROVE")
        self.assertEqual(record["report"], report)

        execution = self.review_execution(worktree.path,gates=[deferred_gate])
        report["coverage"].append({"check": "CI", "status": "BLOCKED", "evidence": "not run yet"})
        result, record = review()
        self.assertEqual(result.returncode, 1, result.stderr)
        self.assertEqual((record["outcome"], record["reason"]),
                         ("INCONCLUSIVE", "invalid_final_output"))
        self.assertEqual(record["validation_error"], "APPROVE verdict contradicts findings")
        self.assertIsNone(record["report"])
        self.assertTrue(record["closeout_eligible"])
        self.assertEqual(record["output_candidate_tree"], tree)
        self.assertEqual(json.loads(Path(record["artifacts"]["final"]).read_text()), report)
        status = json.loads(self.cli("status", record["id"]).stdout)
        self.assertEqual(status["validation_error"], record["validation_error"])
        original = Path(record["artifacts"]["final"]).read_bytes()
        snapshot = self.store.path(execution["id"]) / "plan.md"
        dossier = self.root / "reconcile.json"
        dossier.write_text(json.dumps({"version":1,"conclusion":"APPROVE","findings":[],
            "evidence":[{"path":str(snapshot),"sha256":digest(snapshot.read_bytes())}],
            "reason":"The approved plan defers CI; scope passed and has no findings or blockers"}))
        result = self.cli("reconcile", record["id"], dossier)
        self.assertEqual(result.returncode, 1, result.stderr)
        reconciled = json.loads(result.stdout)
        self.assertEqual((reconciled["outcome"], reconciled["reason"], reconciled["report"], reconciled["validation_error"]),
                         ("INCONCLUSIVE", "invalid_final_output", None, record["validation_error"]))
        self.assertEqual(Path(record["artifacts"]["final"]).read_bytes(), original)
        result = self.cli("review", execution["id"], tree, self.review_dossier(execution),
                          env={"FAKE_MODE":"budget"})
        self.assertEqual(result.returncode, 1, result.stderr)
        cached = json.loads(result.stdout)
        self.assertEqual(cached["id"], record["id"])
        self.assertEqual(self.store.load(execution["id"])["approval"]["source"], "reconciliation")
        self.cli("checkpoint", execution["id"], tree, "--message", "test: evidenced reconciliation", check=True)

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

    def test_stopped_reason_and_missing_zero_positive_usage(self):
        report = {"status":"STOPPED", "steps":["Checked the specification"],
                  "stoppedBecause":"runtime-acceptance.proof is absent", "filesChanged":[], "notes":[]}
        for usage in (None, {"input_tokens":0,"cached_input_tokens":0,"output_tokens":0},
                      {"input_tokens":20,"cached_input_tokens":5,"output_tokens":3}):
            with self.subTest(usage=usage):
                event = {"type":"turn.completed"}
                if usage is not None:
                    event["usage"] = usage
                process = ProcessResult(0, "exit", json.dumps(event).encode(), b"", 0.1, False)
                outcome, reason, actual, metrics = classify(process, json.dumps(report).encode(), report_kind="executor")
                self.assertEqual((outcome, reason, actual), ("STOPPED", "completed", report))
                self.assertEqual(metrics["usage_observed"], usage is not None)
                self.assertEqual(metrics["token_usage"], usage)
        report["stoppedBecause"] = ""
        self.assertEqual(classify(process, json.dumps(report).encode(), report_kind="executor")[1],
                         "invalid_final_output")

    def test_closeout_requires_events_and_captured_candidate(self):
        result = self.cli("execute", self.plan(), self.repo, env={"FAKE_MODE":"budget"})
        self.assertEqual(result.returncode, 1, result.stderr)
        record = json.loads(result.stdout)
        self.assertEqual((record["phase"], record["outcome"], record["reason"], record["closeout_eligible"]),
                         ("finished", "INCONCLUSIVE", "rollout_budget_exhausted", True))
        dossier = self.review_dossier(record)
        capture = self.root / "unexpected-review.json"
        for change in ({"phase":"executing"}, {"closeout_eligible":False}, {"outcome":"STOPPED"}):
            with self.subTest(change=change):
                self.store.save({**record, **change})
                rejected = self.cli("review", record["id"], record["output_candidate_tree"], dossier,
                                    env={"FAKE_MODE":"review", "FAKE_CAPTURE":str(capture)})
                self.assertEqual(rejected.returncode, 2, rejected.stdout)
                self.assertIn("finished complete or closeout-eligible", rejected.stderr)
                self.assertFalse(capture.exists())
        self.store.save(record)
        drift = Path(record["worktree"]) / "later.txt"
        drift.write_text("external drift\n")
        rejected = self.cli("review", record["id"], record["output_candidate_tree"], dossier,
                            env={"FAKE_MODE":"review", "FAKE_CAPTURE":str(capture)})
        self.assertEqual(rejected.returncode, 2, rejected.stdout)
        self.assertIn("candidate", rejected.stderr)
        self.assertFalse(capture.exists())
        drift.unlink()
        review = json.loads(self.cli("review", record["id"], record["output_candidate_tree"], dossier,
                                    env={"FAKE_MODE":"review"}, check=True).stdout)
        self.assertEqual(review["outcome"], "APPROVE")
        self.assertEqual(self.store.load(record["id"])["approval"]["reviewId"], review["id"])
        self.assertEqual((self.store.load(record["id"])["outcome"], self.store.load(record["id"])["reason"]),
                         ("INCONCLUSIVE", "rollout_budget_exhausted"))
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
        for kind, role in (("review", "reviewer"), ("scout", "scout")):
            worktree = self.worktree(kind)
            probe = self.root / f"{kind}-probe.py"
            probe.write_text("import sys;sys.exit(1)\n")
            probes = [{"argv": [sys.executable, str(probe)], "timeoutSeconds": 2}]
            if kind == "review":
                execution = self.review_execution(worktree.path, probes=probes)
                initial = json.loads(self.cli("review", execution["id"], execution["output_candidate_tree"],
                    self.review_dossier(execution), env={"FAKE_MODE":"review"}, check=True).stdout)
            else:
                record = CLI_FUNCTIONS["_record"](
                    self.store, role=role, worktree=worktree.path, common_dir=worktree.common_dir,
                    branch=worktree.branch, head=worktree.head, tree=candidate(worktree)[1],
                    grants=[], kind=kind)
                with patch.dict(os.environ, self.env):
                    initial = CLI_FUNCTIONS["start"](self.store, record, self.plan(probes).read_bytes(),
                                                    b"Assigned scout prompt and schema.\n")
            assigned = (self.store.path(initial["id"]) / "prompt.txt").read_bytes()
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
        execution = self.review_execution(worktree.path)
        result = self.cli("review", execution["id"], execution["output_candidate_tree"],
                          self.review_dossier(execution), env={"FAKE_MODE": "review"})
        self.assertEqual(result.returncode, 0, result.stderr)
        record = json.loads(result.stdout)
        private_roles = self.root / "roles.json"
        roles = json.loads((SKILL_ROOT / "config/roles.json").read_text())
        roles["reviewer"]["initialTimeout"] += 1
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
        worker["plan_settings"] = parse_plan(plan)
        worker["environment_settings"] = worker["plan_settings"]["environment"]
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
        visual = self.visual_execution(self.worktree())
        initial = json.loads(self.cli("execute", self.plan(inputs={"visual":{
            "executionId":visual["id"], "inputIds":visual["report"]["inputIds"], "report":True}}), self.repo,
                                      env={"FAKE_CAPTURE": "change.txt"}, check=True).stdout)
        findings = self.root / "findings.md"
        findings.write_text("Finding: specific observed review defect.\n")
        first = json.loads(self.cli("revise", initial["id"], findings,
                                    "--expected-tree", initial["output_candidate_tree"], check=True).stdout)
        second = json.loads(self.cli("revise", first["id"], findings,
                                     "--expected-tree", first["output_candidate_tree"], check=True).stdout)
        self.assertNotEqual(self.cli("revise", second["id"], findings,
                                     "--expected-tree", second["output_candidate_tree"]).returncode, 0)
        approved = self.cli("review", second["id"], second["output_candidate_tree"],
                            self.review_dossier(second),env={"FAKE_MODE":"review"},check=True)
        self.assertEqual(json.loads(approved.stdout)["outcome"],"APPROVE")
        point = json.loads(self.cli("checkpoint", second["id"],
                                    second["output_candidate_tree"], "--message", "feat: reviewed",
                                    check=True).stdout)["checkpoint_oid"]
        image = image_paths(self.store, second)[0]
        unavailable = image.with_suffix(".unavailable")
        image.rename(unavailable)
        capture = self.root / "unexpected-next.json"
        executions = set(self.store.executions.iterdir())
        worktrees = set(self.store.worktrees.iterdir())
        rejected = self.cli("next", second["id"], point, self.plan(), env={"FAKE_CAPTURE":str(capture)})
        self.assertEqual(rejected.returncode, 2, rejected.stdout)
        self.assertIn("input is unreadable", rejected.stderr)
        self.assertFalse(capture.exists())
        self.assertFalse(self.store.load(second["id"])["consumed"])
        self.assertEqual(set(self.store.executions.iterdir()), executions)
        self.assertEqual(set(self.store.worktrees.iterdir()), worktrees)
        unavailable.rename(image)
        next_run = self.cli("next", second["id"], point, self.plan(),
                            env={"FAKE_CAPTURE":"successor-change.txt"})
        self.assertEqual(next_run.returncode, 0, next_run.stderr)
        successor = json.loads(next_run.stdout)
        self.assertNotEqual(successor["worktree"], second["worktree"])
        self.assertTrue(Path(second["worktree"]).is_dir())
        self.assertEqual(successor["base_head"], point)
        self.assertEqual(json.loads(self.cli("candidate", successor["worktree"], check=True).stdout)["tree"],
                         successor["output_candidate_tree"])
        self.assertNotEqual(self.cli("next", second["id"], point, self.plan()).returncode, 0)
        tree = successor["output_candidate_tree"]
        dossier = self.review_dossier(successor)
        self.cli("review", successor["id"], tree, dossier, env={"FAKE_MODE":"review"}, check=True)
        point = json.loads(self.cli("checkpoint", successor["id"], tree,
            "--message", "test: reviewed successor", check=True).stdout)["checkpoint_oid"]
        data = json.loads(dossier.read_text())
        data["head"] = point
        dossier.write_text(json.dumps(data))
        latest = json.loads(self.cli("review", successor["id"], tree, dossier,
            env={"FAKE_MODE":"review", "FAKE_REVIEW_REPORT":json.dumps(self.revise_report())}, check=True).stdout)
        self.assertEqual(latest["outcome"], "REVISE")
        capture = self.root / "unexpected-successor.json"
        executions = set(self.store.executions.iterdir())
        rejected = self.cli("next", successor["id"], point, self.plan(), env={"FAKE_CAPTURE":str(capture)})
        self.assertEqual(rejected.returncode, 2, rejected.stdout)
        self.assertIn("approval", rejected.stderr)
        self.assertFalse(capture.exists())
        self.assertFalse(self.store.load(successor["id"])["consumed"])
        self.assertEqual(set(self.store.executions.iterdir()), executions)
        self.cli("review", successor["id"], tree, dossier, env={"FAKE_MODE":"review"}, check=True)
        self.cli("next", successor["id"], point, self.plan(), check=True)

    def test_checkpoint_integration_binds_execution_target_and_merge_tree(self):
        worktree = self.worktree()
        (worktree.path / "tracked.txt").write_text("reviewed\n")
        execution = self.review_execution(worktree.path)
        tree = execution["output_candidate_tree"]
        dossier = self.review_dossier(execution)
        self.cli("review", execution["id"], tree, dossier, env={"FAKE_MODE":"review"}, check=True)
        oid = json.loads(self.cli("checkpoint", execution["id"], tree,
            "--message", "test: reviewed checkpoint", check=True).stdout)["checkpoint_oid"]
        rejected = self.cli("checkpoint", execution["id"], "--integrate-oid", oid,
                            "--target", self.repo, "--expected-target", self.base)
        self.assertEqual(rejected.returncode, 2)
        data = json.loads(dossier.read_text())
        data.update(head=oid, target={"worktree":str(self.repo),"head":self.base,"mergeTree":tree})
        dossier.write_text(json.dumps(data))
        self.cli("review", execution["id"], tree, dossier, env={"FAKE_MODE":"review"}, check=True)
        for source, target in ((self.base, self.base), (oid, "0" * 40)):
            rejected = self.cli("checkpoint", execution["id"], "--integrate-oid", source,
                                "--target", self.repo, "--expected-target", target)
            self.assertEqual(rejected.returncode, 2)
            self.assertEqual(git(self.repo, "rev-parse", "HEAD"), self.base)
        run("git", "-C", self.repo, "commit", "--allow-empty", "-qm", "test: target drift")
        target_head = git(self.repo, "rev-parse", "HEAD")
        rejected = self.cli("checkpoint", execution["id"], "--integrate-oid", oid,
                            "--target", self.repo, "--expected-target", self.base)
        self.assertEqual(rejected.returncode, 2)
        self.assertIn("target drift", rejected.stderr)
        self.assertEqual(git(self.repo, "rev-parse", "HEAD"), target_head)
        data["target"]["head"] = target_head
        dossier.write_text(json.dumps(data))
        self.cli("review", execution["id"], tree, dossier, env={"FAKE_MODE":"review"}, check=True)
        result = self.cli("checkpoint", execution["id"], "--integrate-oid", oid,
                          "--target", self.repo, "--expected-target", target_head, check=True)
        integrated = json.loads(result.stdout)["integrated_oid"]
        self.assertEqual((git(self.repo, "rev-parse", "HEAD^1"), git(self.repo, "rev-parse", "HEAD^2")),
                         (target_head, oid))
        self.assertEqual(git(self.repo, "rev-parse", f"{integrated}^{{tree}}"), tree)

    def test_review_rejects_postrun_drift(self):
        worktree = self.worktree()
        execution = self.review_execution(worktree.path)
        tree = candidate(worktree)[1]
        result = self.cli("review", execution["id"], tree, self.review_dossier(execution),
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

    def test_cancel_during_start_preserves_evidence(self):
        ready = self.root / "ready"
        script = ("import pathlib,signal,sys,time\n"
                  "signal.signal(signal.SIGINT, signal.SIG_IGN)\n"
                  "print('partial-evidence', flush=True)\n"
                  "print('partial-diagnostic', file=sys.stderr, flush=True)\n"
                  "pathlib.Path(sys.argv[1]).touch()\n"
                  "time.sleep(30)\n")
        events, diagnostics = bytearray(), bytearray()
        handlers = {sig: signal.getsignal(sig) for sig in (signal.SIGINT, signal.SIGTERM)}

        def cancel_during_start(_pid):
            deadline = time.monotonic() + 5
            while not ready.exists():
                if time.monotonic() >= deadline:
                    self.fail("child did not emit evidence before startup cancellation")
                time.sleep(0.01)
            os.kill(os.getpid(), signal.SIGINT)

        with patch.dict(run_process.__globals__, {"KILL_GRACE_SECONDS": 0.05}):
            try:
                process = run_process([sys.executable, "-c", script, str(ready)],
                                      cwd=self.repo, env=self.env, deadline=10,
                                      on_start=cancel_during_start,
                                      on_stdout=events.extend, on_stderr=diagnostics.extend)
            except KeyboardInterrupt:
                self.fail("startup cancellation bypassed the supervisor's signal handler")
        self.assertEqual(process.reason, "caller_signal")
        self.assertEqual(process.status, -signal.SIGKILL)
        self.assertEqual(process.stdout, b"partial-evidence\n")
        self.assertEqual(process.stderr, b"partial-diagnostic\n")
        self.assertEqual(events, process.stdout)
        self.assertEqual(diagnostics, process.stderr)
        for sig, handler in handlers.items():
            self.assertEqual(signal.getsignal(sig), handler)

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
        record["plan_settings"] = parse_plan(plan)
        record["environment_settings"] = record["plan_settings"]["environment"]
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

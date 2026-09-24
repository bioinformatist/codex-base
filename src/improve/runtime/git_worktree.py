"""Worktrunk lifecycle and the Git operations Worktrunk cannot bind to an OID."""

from __future__ import annotations

import json
import hashlib
import os
import re
import shutil
import stat
import subprocess
import tempfile
import uuid
from dataclasses import dataclass
from pathlib import Path


class BoundaryError(ValueError):
    pass


def command(argv: list[str], *, cwd: Path | None = None, env: dict[str, str] | None = None,
            input_text: str | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    try:
        result = subprocess.run(argv, cwd=cwd, env=env, input=input_text, text=True,
                                capture_output=True, check=False)
    except FileNotFoundError as exc:
        raise BoundaryError(f"missing required command: {argv[0]}") from exc
    if check and result.returncode:
        detail = result.stderr.strip().splitlines()[-1:] or result.stdout.strip().splitlines()[-1:]
        raise BoundaryError(f"{argv[0]} failed ({result.returncode}): {detail[0] if detail else 'no diagnostic'}")
    return result


def git(root: Path, *args: str, env: dict[str, str] | None = None,
        check: bool = True) -> str:
    return command(["git", "-C", str(root), *args], env=env, check=check).stdout.strip()


def _strict_json(source: str) -> object:
    def pairs(values: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in values:
            if key in result:
                raise BoundaryError(f"duplicate JSON key: {key}")
            result[key] = value
        return result

    def bad_constant(value: str) -> None:
        raise BoundaryError(f"nonfinite JSON number: {value}")

    try:
        return json.loads(source, object_pairs_hook=pairs, parse_constant=bad_constant)
    except (json.JSONDecodeError, TypeError) as exc:
        raise BoundaryError("invalid JSON output") from exc


WT_CONFIG = ("list.json-schema=2", "list.full=false", "list.summary=false",
             'commit.generation.command=""')


def wt(root: Path, *args: str, settings: tuple[str, ...] = ()) -> object:
    argv = ["wt", "-C", str(root)]
    for setting in (*WT_CONFIG, *settings):
        argv.extend(["--config-set", setting])
    result = command([*argv, *args])
    return _strict_json(result.stdout)


def wt_items(root: Path) -> list[dict[str, object]]:
    value = wt(root, "list", "--format=json")
    if not isinstance(value, dict) or value.get("schema") != 2:
        raise BoundaryError("invalid Worktrunk list envelope")
    items = value.get("items")
    if not isinstance(items, list) or any(not isinstance(item, dict) for item in items):
        raise BoundaryError("invalid Worktrunk list items")
    return items


@dataclass(frozen=True)
class Worktree:
    path: Path
    branch: str
    head: str
    common_dir: Path


def _worktree_record(root: Path, path: Path) -> dict[str, object]:
    found = []
    for item in wt_items(root):
        worktree = item.get("worktree")
        if isinstance(worktree, dict) and isinstance(worktree.get("path"), str):
            if Path(worktree["path"]).resolve() == path:
                found.append(item)
    if len(found) != 1:
        raise BoundaryError("worktree is absent or ambiguous in Worktrunk list")
    return found[0]


def validate_worktree(path: str | Path, *, state_root: Path | None = None,
                      owned: bool = True) -> Worktree:
    target = Path(path).resolve(strict=True)
    if not target.is_dir() or Path(git(target, "rev-parse", "--show-toplevel")).resolve() != target:
        raise BoundaryError("worktree must be a Git root")
    git_dir = Path(git(target, "rev-parse", "--path-format=absolute", "--git-dir")).resolve()
    common = Path(git(target, "rev-parse", "--path-format=absolute", "--git-common-dir")).resolve()
    if owned and git_dir == common:
        raise BoundaryError("worktree must be linked")
    branch = git(target, "symbolic-ref", "--quiet", "--short", "HEAD", check=owned)
    if owned and not branch.startswith("codex/improve-"):
        raise BoundaryError("worktree branch is not owned by Improve")
    head = git(target, "rev-parse", "--verify", "HEAD")
    item = _worktree_record(target, target)
    wt_head = item.get("head")
    if item.get("branch") != (branch or None) or not isinstance(wt_head, dict) or wt_head.get("sha") != head:
        raise BoundaryError("Worktrunk branch or HEAD does not match Git")
    if state_root is not None and target.parent != state_root.resolve():
        raise BoundaryError("worktree path is outside the owned state directory")
    return Worktree(target, branch, head, common)


def create_worktree(repository: Path, branch: str, base: str, state_root: Path) -> Worktree:
    if not re.fullmatch(r"codex/improve-[A-Za-z0-9._-]+", branch):
        raise BoundaryError("invalid Improve branch")
    require_oid(repository, base, "commit")
    state_root = state_root.absolute()
    state_root.mkdir(parents=True, exist_ok=True, mode=0o700)
    root_info = state_root.lstat()
    if (not stat.S_ISDIR(root_info.st_mode) or root_info.st_uid != os.getuid() or
        stat.S_IMODE(root_info.st_mode) != 0o700 or state_root.resolve() != state_root):
        raise BoundaryError("owned state root must be a physical private user directory")
    prior_paths = set(state_root.iterdir())
    settings = (f'worktree-path="{state_root}/{{{{ branch | sanitize }}}}"',)
    result = wt(repository, "switch", "--create", branch, "--base", base,
                "--no-cd", "--no-hooks", "--format=json", settings=settings)
    if not isinstance(result, dict):
        raise BoundaryError("invalid Worktrunk create result")
    item = next((value for value in (result.get("path"), result.get("worktree_path"),
                                    result.get("worktree")) if isinstance(value, str)), None)
    if item is None:
        raise BoundaryError("Worktrunk create did not return a path")
    path = Path(item)
    if (not path.is_absolute() or path.parent != state_root or path in prior_paths or
        path.resolve(strict=True) != path):
        raise BoundaryError("Worktrunk did not create a new physical owned path")
    path_info = path.lstat()
    if not stat.S_ISDIR(path_info.st_mode) or path_info.st_uid != os.getuid():
        raise BoundaryError("new worktree root is not a physical user directory")
    created = validate_worktree(path, state_root=state_root)
    if created.branch != branch or created.head != base:
        raise BoundaryError("Worktrunk created a different branch or base")
    if created.common_dir != Path(git(repository, "rev-parse", "--path-format=absolute",
                                      "--git-common-dir")).resolve():
        raise BoundaryError("Worktrunk created a worktree in another repository")
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        current = os.fstat(descriptor)
        if (current.st_uid != os.getuid() or
            (current.st_dev, current.st_ino) != (path_info.st_dev, path_info.st_ino)):
            raise BoundaryError("new worktree root changed before permission update")
        os.fchmod(descriptor, 0o700)
    finally:
        os.close(descriptor)
    return created


def copy_ignored(source: Worktree, target: Worktree, includes: list[str]) -> object:
    if source.common_dir != target.common_dir:
        raise BoundaryError("cache source and target are different repositories")
    include = source.path / ".worktreeinclude"
    if not include.is_file() or include.is_symlink():
        raise BoundaryError("cache copy requires a physical .worktreeinclude")
    lines = [line.strip() for line in include.read_text().splitlines()
             if line.strip() and not line.lstrip().startswith("#")]
    if not includes or sorted(lines) != sorted(includes) or any(
        "\n" in item or "\0" in item for item in includes
    ):
        raise BoundaryError("cache include set differs from .worktreeinclude")
    return wt(source.path, "step", "copy-ignored", "--from", source.branch,
              "--to", target.branch, "--require-include", "--format=json")


def candidate(worktree: Worktree) -> tuple[str, str]:
    if git(worktree.path, "ls-files", "-u"):
        raise BoundaryError("worktree index contains unresolved entries")
    head = git(worktree.path, "rev-parse", "--verify", "HEAD")
    handle, index = tempfile.mkstemp(prefix="codex-improve-index-")
    os.close(handle)
    environment = dict(os.environ, GIT_INDEX_FILE=index)
    try:
        real_index = Path(git(worktree.path, "rev-parse", "--path-format=absolute",
                              "--git-path", "index"))
        if real_index.exists():
            shutil.copyfile(real_index, index)
        else:
            os.unlink(index)
            git(worktree.path, "read-tree", "HEAD", env=environment)
        git(worktree.path, "add", "-A", env=environment)
        tree = git(worktree.path, "write-tree", env=environment)
        return head, tree
    finally:
        for name in (index, f"{index}.lock"):
            try:
                os.unlink(name)
            except FileNotFoundError:
                pass


def require_candidate(worktree: Worktree, expected: str) -> tuple[str, str]:
    require_oid(worktree.path, expected, "tree")
    identity = candidate(worktree)
    if identity[1] != expected:
        raise BoundaryError("candidate tree does not match expected tree")
    return identity


def require_oid(root: Path, expected: str, kind: str) -> str:
    length = 64 if git(root, "rev-parse", "--show-object-format") == "sha256" else 40
    if not re.fullmatch(rf"[0-9a-f]{{{length}}}", expected):
        raise BoundaryError(f"expected {kind} must be a full object ID")
    result = command(["git", "-C", str(root), "cat-file", "-t", expected], check=False)
    if result.returncode or result.stdout.strip() != kind:
        raise BoundaryError(f"expected object is not a {kind}")
    return expected


def checkpoint(worktree: Worktree, expected: str, message: str) -> str:
    if not message.strip():
        raise BoundaryError("commit message is empty")
    parent, tree = require_candidate(worktree, expected)
    if tree == git(worktree.path, "rev-parse", "HEAD^{tree}"):
        raise BoundaryError("candidate is identical to HEAD")
    original_ref = f"refs/heads/{worktree.branch}"
    if git(worktree.path, "symbolic-ref", "HEAD") != original_ref:
        raise BoundaryError("worktree is not attached to the expected branch")
    git(worktree.path, "add", "-A")
    if git(worktree.path, "write-tree") != tree:
        raise BoundaryError("staged tree changed before checkpoint")
    internal_ref = f"refs/codex-improve/checkpoints/{uuid.uuid4().hex}"
    git(worktree.path, "update-ref", internal_ref, parent, "")
    attached = False
    try:
        git(worktree.path, "symbolic-ref", "HEAD", internal_ref)
        attached = True
        command(["git", "-C", str(worktree.path), "commit", "-m", message])
        oid = git(worktree.path, "rev-parse", "--verify", internal_ref)
        if git(worktree.path, "rev-parse", f"{oid}^{{tree}}") != tree:
            raise BoundaryError("Git hook changed the reviewed tree")
        if git(worktree.path, "rev-parse", f"{oid}^1") != parent:
            raise BoundaryError("Git hook changed the checkpoint parent")
        git(worktree.path, "update-ref", original_ref, oid, parent)
        return oid
    finally:
        if attached:
            git(worktree.path, "symbolic-ref", "HEAD", original_ref)
        git(worktree.path, "update-ref", "-d", internal_ref, check=False)


def integrate_exact(target: Path, source_oid: str, expected_target_oid: str) -> str:
    """Integrate an approved source OID without checking out a different source.

    The target may have nonconflicting dirt. Git's merge performs the checkout;
    we preflight its tree and refuse drift, conflicts, and hook mutation.
    """
    require_oid(target, source_oid, "commit")
    require_oid(target, expected_target_oid, "commit")
    if git(target, "rev-parse", "HEAD") != expected_target_oid:
        raise BoundaryError("target HEAD drifted")
    merge_base = git(target, "merge-base", expected_target_oid, source_oid)
    probe = command(["git", "-C", str(target), "merge-tree", "--write-tree",
                     "--merge-base", merge_base, expected_target_oid, source_oid], check=False)
    if probe.returncode:
        raise BoundaryError("approved source conflicts with target")
    merged_tree = probe.stdout.splitlines()[0]
    changed = set(command(["git", "-C", str(target), "diff-tree", "--no-commit-id",
                           "--name-only", "-r", "-z", expected_target_oid,
                           merged_tree]).stdout.strip("\0").split("\0"))
    status = command(["git", "-C", str(target), "status", "--porcelain=v1", "-z",
                      "--untracked-files=all", "--ignored=matching"]).stdout
    fields = status.split("\0")
    dirty_paths: set[str] = set()
    index = 0
    while index < len(fields) and fields[index]:
        entry = fields[index]
        dirty_paths.add(entry[3:])
        if entry[:2] in ("R ", " R", "RR", "C ", " C"):
            index += 1
            dirty_paths.add(fields[index])
        index += 1
    if any(a == b or a.startswith(b.rstrip("/") + "/") or
           b.startswith(a.rstrip("/") + "/") for a in changed for b in dirty_paths):
        raise BoundaryError("target dirt overlaps approved source")
    dirt_before = {name: _fingerprint(target / name) for name in dirty_paths}
    if git(target, "rev-parse", "HEAD") != expected_target_oid:
        raise BoundaryError("target HEAD drifted before merge")
    result = command(["git", "-C", str(target), "merge", "--no-ff", "--no-edit", source_oid], check=False)
    if result.returncode:
        raise BoundaryError("Git merge stopped; inspect target state before any recovery")
    oid = git(target, "rev-parse", "HEAD")
    if git(target, "rev-parse", f"{oid}^2") != source_oid or git(target, "rev-parse", f"{oid}^1") != expected_target_oid:
        raise BoundaryError("integration parents differ from approved OIDs")
    if git(target, "rev-parse", f"{oid}^{{tree}}") != merged_tree:
        raise BoundaryError("integration tree differs from preflight")
    if {name: _fingerprint(target / name) for name in dirty_paths} != dirt_before:
        raise BoundaryError("integration changed nonconflicting target dirt")
    return oid


def _fingerprint(path: Path) -> str:
    """Record local dirt, including ignored directory contents, without following links."""
    digest = hashlib.sha256()

    def visit(item: Path) -> None:
        try:
            info = item.lstat()
        except FileNotFoundError:
            digest.update(b"missing\0")
            return
        digest.update(f"{stat.S_IFMT(info.st_mode)}:{stat.S_IMODE(info.st_mode)}:".encode())
        if stat.S_ISLNK(info.st_mode):
            digest.update(os.readlink(item).encode())
        elif stat.S_ISDIR(info.st_mode):
            for child in sorted(item.iterdir(), key=lambda entry: entry.name):
                digest.update(child.name.encode() + b"\0")
                visit(child)
        elif stat.S_ISREG(info.st_mode):
            with item.open("rb") as source:
                for chunk in iter(lambda: source.read(1024 * 1024), b""):
                    digest.update(chunk)
        else:
            raise BoundaryError("target dirt contains an unsupported file type")

    visit(path)
    return digest.hexdigest()

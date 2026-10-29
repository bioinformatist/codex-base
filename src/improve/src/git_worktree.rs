use crate::{Result, contracts::*, ensure};
use nix::{libc, unistd::getuid};
use serde_json::{Value, json};
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File, OpenOptions},
    io::Read,
    os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
    process::{Command, Output},
};

pub fn command(
    argv: &[String],
    cwd: Option<&Path>,
    env: &BTreeMap<String, String>,
    check: bool,
) -> Result<Output> {
    let mut cmd = Command::new(&argv[0]);
    cmd.args(&argv[1..]).envs(env);
    if let Some(cwd) = cwd {
        cmd.current_dir(cwd);
    }
    let out = cmd.output().map_err(|e| {
        format!(
            "missing required command or failed to start {}: {e}",
            argv[0]
        )
    })?;
    if check && !out.status.success() {
        let err = String::from_utf8_lossy(&out.stderr);
        let stdout = String::from_utf8_lossy(&out.stdout);
        return Err(format!(
            "{} failed ({}): {}",
            argv[0],
            out.status,
            err.trim()
                .lines()
                .last()
                .or_else(|| stdout.trim().lines().last())
                .unwrap_or("no diagnostic")
        )
        .into());
    }
    Ok(out)
}
fn git_raw(
    root: &Path,
    args: &[&str],
    env: &BTreeMap<String, String>,
    check: bool,
) -> Result<String> {
    let argv = [
        vec!["git".into(), "-C".into(), root.display().to_string()],
        args.iter().map(|s| s.to_string()).collect(),
    ]
    .concat();
    Ok(String::from_utf8(command(&argv, None, env, check)?.stdout)?)
}
pub fn git_env(
    root: &Path,
    args: &[&str],
    env: &BTreeMap<String, String>,
    check: bool,
) -> Result<String> {
    Ok(git_raw(root, args, env, check)?.trim().to_owned())
}
fn git_paths(root: &Path, args: &[&str]) -> Result<String> {
    git_raw(root, args, &BTreeMap::new(), true)
}
pub fn git(root: &Path, args: &[&str]) -> Result<String> {
    git_env(root, args, &BTreeMap::new(), true)
}
pub fn wt(root: &Path, args: &[&str], settings: &[String]) -> Result<Value> {
    let mut argv = vec!["wt".into(), "-C".into(), root.display().to_string()];
    for setting in [
        "list.json-schema=2",
        "list.full=false",
        "list.summary=false",
        "commit.generation.command=\"\"",
    ]
    .iter()
    .map(|s| s.to_string())
    .chain(settings.iter().cloned())
    {
        argv.extend(["--config-set".into(), setting]);
    }
    argv.extend(args.iter().map(|s| s.to_string()));
    strict_json(&command(&argv, None, &BTreeMap::new(), true)?.stdout)
}
#[derive(Clone)]
pub struct Worktree {
    pub path: PathBuf,
    pub branch: String,
    pub head: String,
    pub common_dir: PathBuf,
}
pub fn validate_worktree(path: &Path, owned: bool) -> Result<Worktree> {
    let target = path.canonicalize()?;
    ensure(
        target.is_dir()
            && PathBuf::from(git(&target, &["rev-parse", "--show-toplevel"])?).canonicalize()?
                == target,
        "worktree must be a Git root",
    )?;
    let git_dir = PathBuf::from(git(
        &target,
        &["rev-parse", "--path-format=absolute", "--git-dir"],
    )?)
    .canonicalize()?;
    let common = PathBuf::from(git(
        &target,
        &["rev-parse", "--path-format=absolute", "--git-common-dir"],
    )?)
    .canonicalize()?;
    ensure(!owned || git_dir != common, "worktree must be linked")?;
    let branch = git_env(
        &target,
        &["symbolic-ref", "--quiet", "--short", "HEAD"],
        &BTreeMap::new(),
        owned,
    )?;
    ensure(
        !owned || branch.starts_with("codex/improve-"),
        "worktree branch is not owned by Improve",
    )?;
    let head = git(&target, &["rev-parse", "--verify", "HEAD"])?;
    let listing = wt(&target, &["list", "--format=json"], &[])?;
    ensure(
        listing["schema"].as_u64() == Some(2),
        "invalid Worktrunk list envelope",
    )?;
    let mut found = Vec::new();
    for item in array(&listing["items"])? {
        ensure(item.is_object(), "invalid Worktrunk list items")?;
        if let Some(path) = item["worktree"]["path"].as_str() {
            if Path::new(path).canonicalize()? == target {
                found.push(item);
            }
        }
    }
    ensure(
        found.len() == 1,
        "worktree is absent or ambiguous in Worktrunk list",
    )?;
    ensure(
        found[0]["branch"]
            == if branch.is_empty() {
                Value::Null
            } else {
                json!(branch)
            }
            && found[0]["head"]["sha"] == head,
        "Worktrunk branch or HEAD does not match Git",
    )?;
    Ok(Worktree {
        path: target,
        branch,
        head,
        common_dir: common,
    })
}
pub fn require_oid(root: &Path, expected: &str, kind: &str) -> Result<()> {
    let length = if git(root, &["rev-parse", "--show-object-format"])? == "sha256" {
        64
    } else {
        40
    };
    ensure(
        id(expected, length),
        format!("expected {kind} must be a full object ID"),
    )?;
    ensure(
        git_env(root, &["cat-file", "-t", expected], &BTreeMap::new(), false)? == kind,
        format!("expected object is not a {kind}"),
    )
}
pub fn create_worktree(repo: &Path, branch: &str, base: &str, root: &Path) -> Result<Worktree> {
    let suffix = branch.strip_prefix("codex/improve-").unwrap_or("");
    ensure(
        !suffix.is_empty()
            && suffix
                .bytes()
                .all(|b| b.is_ascii_alphanumeric() || b"._-".contains(&b)),
        "invalid Improve branch",
    )?;
    require_oid(repo, base, "commit")?;
    crate::state::private_stat(root, true)?;
    ensure(
        root.canonicalize()? == root,
        "owned state root must be physical",
    )?;
    let prior: BTreeSet<_> = fs::read_dir(root)?
        .map(|e| e.map(|e| e.path()))
        .collect::<std::io::Result<_>>()?;
    let settings = vec![format!(
        "worktree-path={}",
        json!(format!("{}/{{{{ branch | sanitize }}}}", root.display()))
    )];
    let result = wt(
        repo,
        &[
            "switch",
            "--create",
            branch,
            "--base",
            base,
            "--no-cd",
            "--no-hooks",
            "--format=json",
        ],
        &settings,
    )?;
    let path = ["path", "worktree_path", "worktree"]
        .iter()
        .find_map(|k| result[k].as_str())
        .ok_or("Worktrunk create did not return a path")?;
    let path = PathBuf::from(path);
    ensure(
        path.is_absolute()
            && path.parent() == Some(root)
            && !prior.contains(&path)
            && path.canonicalize()? == path,
        "Worktrunk did not create a new physical owned path",
    )?;
    let before = fs::symlink_metadata(&path)?;
    ensure(
        before.is_dir() && before.uid() == getuid().as_raw(),
        "new worktree root is not a physical user directory",
    )?;
    let created = validate_worktree(&path, true)?;
    ensure(
        created.branch == branch
            && created.head == base
            && created.common_dir
                == PathBuf::from(git(
                    repo,
                    &["rev-parse", "--path-format=absolute", "--git-common-dir"],
                )?)
                .canonicalize()?,
        "Worktrunk created a different branch, base or repository",
    )?;
    let file = OpenOptions::new()
        .read(true)
        .custom_flags(libc::O_DIRECTORY | libc::O_NOFOLLOW)
        .open(path)?;
    let current = file.metadata()?;
    ensure(
        current.uid() == getuid().as_raw()
            && (current.dev(), current.ino()) == (before.dev(), before.ino()),
        "new worktree root changed before permission update",
    )?;
    file.set_permissions(fs::Permissions::from_mode(0o700))?;
    Ok(created)
}
pub fn copy_ignored(source: &Worktree, target: &Worktree, includes: &[String]) -> Result<()> {
    ensure(
        source.common_dir == target.common_dir,
        "cache source and target are different repositories",
    )?;
    let include = source.path.join(".worktreeinclude");
    let m = fs::symlink_metadata(&include)?;
    ensure(
        m.is_file() && !m.is_symlink(),
        "cache copy requires a physical .worktreeinclude",
    )?;
    let text = fs::read_to_string(include)?;
    let mut lines: Vec<_> = text
        .lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .collect();
    let mut supplied: Vec<_> = includes.iter().map(String::as_str).collect();
    lines.sort();
    supplied.sort();
    ensure(
        !includes.is_empty()
            && lines == supplied
            && includes.iter().all(|s| !s.contains(['\n', '\0'])),
        "cache include set differs from .worktreeinclude",
    )?;
    wt(
        &source.path,
        &[
            "step",
            "copy-ignored",
            "--from",
            &source.branch,
            "--to",
            &target.branch,
            "--require-include",
            "--format=json",
        ],
        &[],
    )?;
    Ok(())
}
pub fn candidate(worktree: &Worktree) -> Result<(String, String)> {
    ensure(
        git(&worktree.path, &["ls-files", "-u"])?.is_empty(),
        "worktree index contains unresolved entries",
    )?;
    let head = git(&worktree.path, &["rev-parse", "--verify", "HEAD"])?;
    let index = tempfile::NamedTempFile::new()?;
    let real = PathBuf::from(git(
        &worktree.path,
        &["rev-parse", "--path-format=absolute", "--git-path", "index"],
    )?);
    let env = BTreeMap::from([("GIT_INDEX_FILE".into(), index.path().display().to_string())]);
    if real.exists() {
        fs::copy(real, index.path())?;
    } else {
        fs::remove_file(index.path())?;
        git_env(&worktree.path, &["read-tree", "HEAD"], &env, true)?;
    }
    let result = (|| {
        git_env(&worktree.path, &["add", "-A"], &env, true)?;
        Ok((head, git_env(&worktree.path, &["write-tree"], &env, true)?))
    })();
    let _ = fs::remove_file(format!("{}.lock", index.path().display()));
    result
}
pub fn require_candidate(worktree: &Worktree, expected: &str) -> Result<(String, String)> {
    require_oid(&worktree.path, expected, "tree")?;
    let identity = candidate(worktree)?;
    ensure(
        identity.1 == expected,
        "candidate tree does not match expected tree",
    )?;
    Ok(identity)
}
fn match_char(name: char, pattern: &[char]) -> (bool, usize) {
    if pattern.first() != Some(&'[') {
        return (pattern.first().is_some_and(|&c| c == '?' || c == name), 1);
    }
    let start = 1 + usize::from(pattern.get(1) == Some(&'!'));
    let end = start + usize::from(pattern.get(start) == Some(&']'));
    let Some(end) = pattern[end..]
        .iter()
        .position(|&c| c == ']')
        .map(|i| end + i)
    else {
        return (name == '[', 1);
    };
    let mut class = &pattern[start..end];
    let mut negated = start == 2;
    let mut first = !negated;
    let mut hit = false;
    while !class.is_empty() {
        let used = if class.len() >= 3 && class[1] == '-' {
            3
        } else {
            1
        };
        let (lo, hi) = (class[0], class[used - 1]);
        class = &class[used..];
        if lo > hi {
            continue;
        }
        // Python removes reversed ranges before interpreting a leading '!'.
        if first && lo == '!' {
            negated = true;
            hit |= used == 3 && (name == '-' || name == hi);
        } else {
            hit |= lo <= name && name <= hi;
        }
        first = false;
    }
    (hit != negated, end + 1)
}
pub fn matches(name: &str, pattern: &str) -> bool {
    // fnmatchcase uses Unicode characters, with no special slash, dot or escape rules.
    let name: Vec<_> = name.chars().collect();
    let pattern: Vec<_> = pattern.chars().collect();
    let (mut n, mut p) = (0, 0);
    let mut star = None;
    while n < name.len() {
        if pattern.get(p) == Some(&'*') {
            p += 1;
            star = Some((p, n));
            continue;
        }
        let (matched, used) = match_char(name[n], &pattern[p..]);
        if matched {
            n += 1;
            p += used;
        } else if let Some((after, start)) = star {
            n = start + 1;
            p = after;
            star = Some((p, n));
        } else {
            return false;
        }
    }
    pattern[p..].iter().all(|&c| c == '*')
}
pub fn check_write_paths(
    w: &Worktree,
    base: &str,
    tree: &str,
    paths: &[String],
    grants: &[String],
) -> Result<()> {
    let changed = git_paths(
        &w.path,
        &[
            "diff-tree",
            "--no-commit-id",
            "--no-renames",
            "--name-only",
            "-r",
            "-z",
            base,
            tree,
        ],
    )?;
    for name in changed.split('\0').filter(|s| !s.is_empty()) {
        let root = name.split('/').next().unwrap();
        ensure(
            root != ".git"
                && (![".agents", ".codex"].contains(&root) || grants.iter().any(|s| s == root))
                && paths.iter().any(|p| matches(name, p)),
            format!("change outside authenticated writePaths: {name}"),
        )?;
    }
    Ok(())
}
pub fn checkpoint(w: &Worktree, expected: &str, message: &str) -> Result<String> {
    ensure(!message.trim().is_empty(), "commit message is empty")?;
    let (parent, tree) = require_candidate(w, expected)?;
    ensure(
        tree != git(&w.path, &["rev-parse", "HEAD^{tree}"])?,
        "candidate is identical to HEAD",
    )?;
    let original_ref = format!("refs/heads/{}", w.branch);
    ensure(
        git(&w.path, &["symbolic-ref", "HEAD"])? == original_ref,
        "worktree is not attached to the expected branch",
    )?;
    git(&w.path, &["add", "-A"])?;
    ensure(
        git(&w.path, &["write-tree"])? == tree,
        "staged tree changed before checkpoint",
    )?;
    let internal = format!("refs/codex-improve/checkpoints/{}", crate::state::new_id()?);
    git(&w.path, &["update-ref", &internal, &parent, ""])?;
    let mut attached = false;
    let result = (|| {
        git(&w.path, &["symbolic-ref", "HEAD", &internal])?;
        attached = true;
        git(&w.path, &["commit", "-m", message])?;
        let oid = git(&w.path, &["rev-parse", "--verify", &internal])?;
        ensure(
            git(&w.path, &["rev-parse", &format!("{oid}^{{tree}}")])? == tree,
            "Git hook changed the reviewed tree",
        )?;
        ensure(
            git(&w.path, &["rev-parse", &format!("{oid}^1")])? == parent,
            "Git hook changed the checkpoint parent",
        )?;
        git(&w.path, &["update-ref", &original_ref, &oid, &parent])?;
        Ok(oid)
    })();
    if attached {
        git(&w.path, &["symbolic-ref", "HEAD", &original_ref])?;
    }
    git_env(
        &w.path,
        &["update-ref", "-d", &internal],
        &BTreeMap::new(),
        false,
    )?;
    result
}
fn fingerprint(path: &Path, hash: &mut sha2::Sha256) -> Result<()> {
    use sha2::Digest;
    let m = match fs::symlink_metadata(path) {
        Ok(m) => m,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
            hash.update(b"missing\0");
            return Ok(());
        }
        Err(e) => return Err(e.into()),
    };
    hash.update(m.mode().to_le_bytes());
    if m.is_symlink() {
        hash.update(fs::read_link(path)?.as_os_str().as_encoded_bytes());
    } else if m.is_dir() {
        let mut entries: Vec<_> = fs::read_dir(path)?.collect::<std::io::Result<_>>()?;
        entries.sort_by_key(|e| e.file_name());
        for entry in entries {
            hash.update(entry.file_name().as_encoded_bytes());
            hash.update(b"\0");
            fingerprint(&entry.path(), hash)?;
        }
    } else if m.is_file() {
        let mut f = File::open(path)?;
        let mut buf = [0; 65536];
        loop {
            let n = f.read(&mut buf)?;
            if n == 0 {
                break;
            }
            hash.update(&buf[..n]);
        }
    } else {
        return Err("target dirt contains an unsupported file type".into());
    }
    Ok(())
}
pub fn integrate_exact(target: &Path, source: &str, expected: &str) -> Result<String> {
    use sha2::Digest;
    require_oid(target, source, "commit")?;
    require_oid(target, expected, "commit")?;
    ensure(
        git(target, &["rev-parse", "HEAD"])? == expected,
        "target HEAD drifted",
    )?;
    let base = git(target, &["merge-base", expected, source])?;
    let probe = git(
        target,
        &[
            "merge-tree",
            "--write-tree",
            "--merge-base",
            &base,
            expected,
            source,
        ],
    )?;
    let merged_tree = probe.lines().next().ok_or("merge-tree returned no tree")?;
    let changed = git_paths(
        target,
        &[
            "diff-tree",
            "--no-commit-id",
            "--name-only",
            "-r",
            "-z",
            expected,
            merged_tree,
        ],
    )?;
    let status = git_paths(
        target,
        &[
            "status",
            "--porcelain=v1",
            "-z",
            "--untracked-files=all",
            "--ignored=matching",
        ],
    )?;
    let mut fields = status.split('\0').filter(|s| !s.is_empty());
    let mut dirt = BTreeSet::new();
    while let Some(entry) = fields.next() {
        ensure(entry.len() >= 3, "invalid Git status")?;
        dirt.insert(entry[3..].to_owned());
        if ["R ", " R", "RR", "C ", " C"].contains(&&entry[..2]) {
            dirt.insert(fields.next().ok_or("invalid rename status")?.to_owned());
        }
    }
    ensure(
        !changed.split('\0').filter(|s| !s.is_empty()).any(|a| {
            dirt.iter().any(|b| {
                a == b
                    || a.starts_with(&format!("{}/", b.trim_end_matches('/')))
                    || b.starts_with(&format!("{}/", a.trim_end_matches('/')))
            })
        }),
        "target dirt overlaps approved source",
    )?;
    let snapshots = || -> Result<Vec<Vec<u8>>> {
        dirt.iter()
            .map(|p| {
                let mut hash = sha2::Sha256::new();
                fingerprint(&target.join(p), &mut hash)?;
                Ok(hash.finalize().to_vec())
            })
            .collect()
    };
    let before = snapshots()?;
    ensure(
        git(target, &["rev-parse", "HEAD"])? == expected,
        "target HEAD drifted before merge",
    )?;
    git(target, &["merge", "--no-ff", "--no-edit", source])
        .map_err(|_| "Git merge stopped; inspect target state before any recovery")?;
    let oid = git(target, &["rev-parse", "HEAD"])?;
    ensure(
        git(target, &["rev-parse", &format!("{oid}^2")])? == source
            && git(target, &["rev-parse", &format!("{oid}^1")])? == expected
            && git(target, &["rev-parse", &format!("{oid}^{{tree}}")])? == merged_tree,
        "integration parents or tree differ from preflight",
    )?;
    ensure(
        snapshots()? == before,
        "integration changed nonconflicting target dirt",
    )?;
    Ok(oid)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn fnmatch_semantics() {
        for (name, pattern, expected) in [
            ("src/a/b", "src/*", true),
            (".agents/x", "*", true),
            ("src/a", "src/?.[ch]", false),
            ("src/a.c", "src/[!b].?", true),
            ("x", "[]", false),
            ("b.rs", "[^a].rs", false),
            ("a.rs", "[^a].rs", true),
            ("^.rs", "[^a].rs", true),
            ("é.rs", "?.rs", true),
            ("é", "[à-ê]", true),
            ("a", "[[:alpha:]]", false),
            ("a]", "[[:alpha:]]", true),
            ("\\a", "\\?", true),
            ("a", "\\a", false),
            ("[]", "[]", true),
            ("[!]", "[!]", true),
            ("]", "[]]", true),
            ("[", "[[]", true),
            ("-", "[a-b-c]", true),
            ("z", "[z-a]", false),
            ("z", "[!z-a]", true),
            ("x", "[z-a!]", true),
            ("b", "[z-a!-b]", false),
            ("x", "[z-a!-b]", true),
            ("A", "a", false),
            ("a\nb", "a?b", true),
            ("ab/cccd", "*b*c?d", true),
            ("ab/cccdx", "*b*c?d", false),
            ("", "**", true),
            ("", "?", false),
        ] {
            assert_eq!(matches(name, pattern), expected, "{name:?} {pattern:?}");
        }
    }
}

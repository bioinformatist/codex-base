use crate::{Result, contracts::*, ensure};
use serde_json::json;
use std::{
    collections::{BTreeMap, BTreeSet},
    fs::{self, File},
    io::Read,
    os::unix::fs::{MetadataExt, PermissionsExt},
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
#[derive(Clone)]
pub struct Worktree {
    pub path: PathBuf,
    pub branch: String,
    pub head: String,
    pub common_dir: PathBuf,
}
pub fn validate_worktree(path: &Path, owned: bool) -> Result<Worktree> {
    require_physical(path)?;
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
        false,
    )?;
    let head = git(&target, &["rev-parse", "--verify", "HEAD"])?;
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
pub fn create_worktree(repo: &Path, task: &str, base: &str, root: &Path) -> Result<Worktree> {
    ensure(id(task, 32), "invalid task ID")?;
    require_oid(repo, base, "commit")?;
    crate::state::private_stat(root, true)?;
    ensure(
        root.canonicalize()? == root,
        "worktree parent must be physical",
    )?;
    let path = root.join(task);
    ensure(
        fs::symlink_metadata(&path).is_err(),
        "worktree path already exists",
    )?;
    let common = validate_worktree(repo, false)?.common_dir;
    let result = (|| {
        git(
            repo,
            &[
                "worktree",
                "add",
                "--detach",
                path.to_str().ok_or("non-UTF8 worktree")?,
                base,
            ],
        )?;
        let created = validate_worktree(&path, true)?;
        ensure(
            created.path == path && created.head == base && created.common_dir == common,
            "created worktree identity differs",
        )?;
        fs::set_permissions(&path, fs::Permissions::from_mode(0o700))?;
        Ok(created)
    })();
    if result.is_err() && path.exists() {
        // Only the new, physical, empty-of-dirt worktree can be rolled back.
        let _ = remove_worktree(&path, &common, base);
    }
    result
}
pub fn require_physical(path: &Path) -> Result<()> {
    let absolute = std::path::absolute(path)?;
    ensure(
        absolute.canonicalize()? == absolute && !fs::symlink_metadata(path)?.is_symlink(),
        "path must be physical",
    )
}
pub fn remove_worktree(path: &Path, common: &Path, expected_head: &str) -> Result<()> {
    require_physical(path)?;
    let w = validate_worktree(path, true)?;
    ensure(
        w.common_dir == common && w.head == expected_head,
        "worktree ownership or HEAD changed",
    )?;
    ensure(
        git(
            path,
            &[
                "status",
                "--porcelain=v1",
                "--untracked-files=all",
                "--ignored=matching",
            ],
        )?
        .is_empty(),
        "dirty or ignored contents prevent removal",
    )?;
    git(
        path,
        &["worktree", "remove", path.to_str().ok_or("non-UTF8 path")?],
    )?;
    Ok(())
}
pub fn copy_ignored(source: &Worktree, target: &Worktree, includes: &[String]) -> Result<()> {
    ensure(
        source.common_dir == target.common_dir && !includes.is_empty(),
        "copy requires same repository and explicit includes",
    )?;
    fn copy(source: &Path, target: &Path) -> Result<()> {
        let m = fs::symlink_metadata(source)?;
        ensure(!m.is_symlink(), "ignored copy contains a symlink")?;
        ensure(
            fs::symlink_metadata(target).is_err(),
            "ignored copy would overwrite contents",
        )?;
        if m.is_file() {
            fs::copy(source, target)?;
        } else {
            ensure(m.is_dir(), "ignored copy contains a special file")?;
            fs::create_dir(target)?;
            for entry in fs::read_dir(source)? {
                let e = entry?;
                copy(&e.path(), &target.join(e.file_name()))?;
            }
        }
        Ok(())
    }
    for name in includes {
        ensure(
            relative_path(&json!(name))
                && ![".git", ".agents", ".codex"].contains(&name.split('/').next().unwrap()),
            "invalid ignored include",
        )?;
        let src = source.path.join(name);
        require_physical(&src)?;
        ensure(
            git(&source.path, &["check-ignore", "--", name])? == *name,
            "include must be ignored",
        )?;
        let dst = target.path.join(name);
        let parent = dst.parent().ok_or("missing include parent")?;
        ensure(
            parent.exists(),
            "include parent must already exist; include its directory explicitly",
        )?;
        require_physical(parent)?;
        copy(&src, &dst)?;
    }
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
    ensure(
        message.split_once(": ").is_some_and(|(kind, summary)| {
            !kind.is_empty()
                && kind.bytes().all(|b| b.is_ascii_lowercase())
                && !summary.trim().is_empty()
        }),
        "checkpoint requires a Conventional Commit message",
    )?;
    let (parent, tree) = require_candidate(w, expected)?;
    ensure(
        tree != git(&w.path, &["rev-parse", "HEAD^{tree}"])?,
        "candidate is identical to HEAD",
    )?;
    let original_ref = git_env(
        &w.path,
        &["symbolic-ref", "--quiet", "HEAD"],
        &BTreeMap::new(),
        false,
    )?;
    ensure(
        (original_ref.is_empty() && w.branch.is_empty())
            || original_ref == format!("refs/heads/{}", w.branch),
        "worktree attachment changed",
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
        if !original_ref.is_empty() {
            git(&w.path, &["update-ref", &original_ref, &oid, &parent])?;
        }
        Ok(oid)
    })();
    if attached {
        if original_ref.is_empty() {
            let restored = result.as_ref().unwrap_or(&parent);
            git(&w.path, &["update-ref", "--no-deref", "HEAD", restored])?;
        } else {
            git(&w.path, &["symbolic-ref", "HEAD", &original_ref])?;
        }
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

#[cfg(test)]
mod workspace_tests {
    use super::*;
    fn repo(root: &Path) -> PathBuf {
        let repo = root.join("repo");
        fs::create_dir(&repo).unwrap();
        for args in [
            vec!["init", "-q"],
            vec!["config", "user.name", "Fixture"],
            vec!["config", "user.email", "fixture@example.invalid"],
        ] {
            git(&repo, &args).unwrap();
        }
        fs::write(repo.join("tracked"), "base").unwrap();
        fs::write(repo.join(".gitignore"), "cache/\n").unwrap();
        git(&repo, &["add", "."]).unwrap();
        git(&repo, &["commit", "-qm", "test: base"]).unwrap();
        repo
    }
    #[test]
    fn exact_base_full_candidate_and_safe_removal() {
        let temp = tempfile::tempdir().unwrap();
        let repo = repo(temp.path());
        let base = git(&repo, &["rev-parse", "HEAD"]).unwrap();
        fs::write(repo.join("tracked"), "newer").unwrap();
        git(&repo, &["commit", "-qam", "test: newer"]).unwrap();
        let parent = crate::state::private_dir(&temp.path().join("workspaces")).unwrap();
        let w = create_worktree(&repo, &crate::state::new_id().unwrap(), &base, &parent).unwrap();
        assert_eq!(fs::read_to_string(w.path.join("tracked")).unwrap(), "base");
        assert!(w.branch.is_empty());
        let index = PathBuf::from(
            git(
                &w.path,
                &["rev-parse", "--path-format=absolute", "--git-path", "index"],
            )
            .unwrap(),
        );
        let original = fs::read(&index).unwrap();
        fs::write(w.path.join("tracked"), "changed").unwrap();
        fs::write(w.path.join("new"), "untracked").unwrap();
        let (_, tree) = candidate(&w).unwrap();
        assert_eq!(fs::read(&index).unwrap(), original);
        assert_eq!(
            git(&w.path, &["show", &format!("{tree}:new")]).unwrap(),
            "untracked"
        );
        assert!(remove_worktree(&w.path, &w.common_dir, &base).is_err());
        fs::remove_file(w.path.join("new")).unwrap();
        git(&w.path, &["restore", "tracked"]).unwrap();
        fs::create_dir(w.path.join("cache")).unwrap();
        fs::write(w.path.join("cache/private"), "keep").unwrap();
        assert!(remove_worktree(&w.path, &w.common_dir, &base).is_err());
        fs::remove_dir_all(w.path.join("cache")).unwrap();
        let alias = temp.path().join("alias");
        std::os::unix::fs::symlink(&w.path, &alias).unwrap();
        assert!(validate_worktree(&alias, true).is_err());
        remove_worktree(&w.path, &w.common_dir, &base).unwrap();
        assert!(!w.path.exists());
    }
    #[test]
    fn explicit_ignored_copy_and_detached_checkpoint() {
        let temp = tempfile::tempdir().unwrap();
        let repo = repo(temp.path());
        let source = validate_worktree(&repo, false).unwrap();
        let parent = crate::state::private_dir(&temp.path().join("workspaces")).unwrap();
        let w = create_worktree(
            &repo,
            &crate::state::new_id().unwrap(),
            &source.head,
            &parent,
        )
        .unwrap();
        fs::create_dir(repo.join("cache")).unwrap();
        fs::write(repo.join("cache/file"), "cache").unwrap();
        assert!(!w.path.join("cache").exists());
        copy_ignored(&source, &w, &["cache".into()]).unwrap();
        assert_eq!(
            fs::read_to_string(w.path.join("cache/file")).unwrap(),
            "cache"
        );
        assert!(copy_ignored(&source, &w, &["cache".into()]).is_err());
        assert!(copy_ignored(&source, &w, &["tracked".into()]).is_err());
        fs::remove_dir_all(w.path.join("cache")).unwrap();
        fs::write(w.path.join("tracked"), "changed").unwrap();
        let (_, tree) = candidate(&w).unwrap();
        let oid = checkpoint(&w, &tree, "feat: reviewed change").unwrap();
        assert_eq!(git(&w.path, &["rev-parse", "HEAD"]).unwrap(), oid);
        assert_eq!(git(&w.path, &["rev-parse", "HEAD^{tree}"]).unwrap(), tree);
        assert_eq!(git(&repo, &["rev-parse", "HEAD"]).unwrap(), source.head);
        assert!(git(&w.path, &["ls-files", "-u"]).unwrap().is_empty());
        assert!(integrate_exact(&repo, &oid, &"0".repeat(40)).is_err());
        let merged = integrate_exact(&repo, &oid, &source.head).unwrap();
        assert_eq!(
            git(&repo, &["rev-parse", &format!("{merged}^2")]).unwrap(),
            oid
        );
    }
}

use crate::{Result, contracts::*, ensure};
use hmac::{Hmac, Mac};
use nix::{
    fcntl::{Flock, FlockArg},
    unistd::getuid,
};
use serde_json::Value;
use sha2::Sha256;
use std::{
    env,
    fs::{self, File, OpenOptions},
    io::{Read, Write},
    os::unix::fs::{DirBuilderExt, MetadataExt, OpenOptionsExt, PermissionsExt},
    path::{Path, PathBuf},
};

pub fn private_stat(path: &Path, directory: bool) -> Result<()> {
    let m = fs::symlink_metadata(path)?;
    ensure(
        !m.is_symlink()
            && m.uid() == getuid().as_raw()
            && m.mode() & 0o777 == if directory { 0o700 } else { 0o600 }
            && if directory { m.is_dir() } else { m.is_file() },
        format!("private state path is unsafe: {}", path.display()),
    )
}
pub fn private_dir(path: &Path) -> Result<PathBuf> {
    match fs::DirBuilder::new().mode(0o700).create(path) {
        Ok(()) => {}
        Err(e) if e.kind() == std::io::ErrorKind::AlreadyExists => {}
        Err(e) => return Err(e.into()),
    }
    private_stat(path, true)?;
    Ok(path.to_owned())
}
pub fn private_read(path: &Path) -> Result<Vec<u8>> {
    private_stat(path, false)?;
    Ok(fs::read(path)?)
}
pub fn private_append(path: &Path) -> Result<File> {
    let file = OpenOptions::new()
        .append(true)
        .custom_flags(nix::libc::O_NOFOLLOW)
        .open(path)?;
    let m = file.metadata()?;
    ensure(
        m.is_file() && m.uid() == getuid().as_raw() && m.mode() & 0o777 == 0o600,
        "private append path is unsafe",
    )?;
    Ok(file)
}
pub fn atomic_private(path: &Path, raw: &[u8]) -> Result<()> {
    if fs::symlink_metadata(path).is_ok() {
        private_stat(path, false)?;
    }
    let mut tmp = tempfile::Builder::new()
        .prefix(".tmp-")
        .tempfile_in(path.parent().ok_or("missing parent")?)?;
    tmp.as_file()
        .set_permissions(fs::Permissions::from_mode(0o600))?;
    tmp.write_all(raw)?;
    tmp.as_file().sync_all()?;
    tmp.persist(path)?;
    Ok(())
}
pub fn new_id() -> Result<String> {
    Ok(hex(&random_bytes::<16>()?))
}
fn random_bytes<const N: usize>() -> Result<[u8; N]> {
    let mut bytes = [0; N];
    File::open("/dev/urandom")?.read_exact(&mut bytes)?;
    Ok(bytes)
}

pub struct StateStore {
    pub root: PathBuf,
    pub executions: PathBuf,
    pub worktrees: PathBuf,
    pub cache: PathBuf,
    key: Vec<u8>,
}
impl StateStore {
    pub fn new(base: Option<&Path>) -> Result<Self> {
        let home = base
            .map(Path::to_owned)
            .or_else(|| env::var_os("XDG_STATE_HOME").map(PathBuf::from))
            .unwrap_or_else(|| {
                PathBuf::from(env::var_os("HOME").unwrap_or_default()).join(".local/state")
            });
        fs::DirBuilder::new()
            .recursive(true)
            .mode(0o700)
            .create(&home)?;
        let m = fs::symlink_metadata(&home)?;
        ensure(
            m.is_dir() && !m.is_symlink() && m.uid() == getuid().as_raw(),
            "state home is not a physical user-owned directory",
        )?;
        let root = private_dir(&home.join("codex-improve-v19"))?;
        let executions = private_dir(&root.join("executions"))?;
        let worktrees = private_dir(&root.join("worktrees"))?;
        let cache = private_dir(&root.join("cache"))?;
        let key_path = root.join("key");
        if fs::symlink_metadata(&key_path).is_err() {
            atomic_private(&key_path, &random_bytes::<32>()?)?;
        }
        let key = private_read(&key_path)?;
        ensure(key.len() == 32, "private state key is invalid")?;
        Ok(Self {
            root,
            executions,
            worktrees,
            cache,
            key,
        })
    }
    pub fn path(&self, execution: &str) -> Result<PathBuf> {
        ensure(id(execution, 32), "invalid execution ID")?;
        Ok(self.executions.join(execution))
    }
    pub fn lock(&self, execution: &str) -> Result<Flock<File>> {
        let path = self.path(execution)?;
        private_stat(&path, true)?;
        Flock::lock(File::open(path)?, FlockArg::LockExclusive).map_err(|(_, e)| e.into())
    }
    pub fn create(&self, record: &mut Value, plan: &[u8], prompt: &[u8]) -> Result<()> {
        let location = self.path(string(&record["id"])?)?;
        ensure(
            fs::symlink_metadata(&location).is_err(),
            "execution ID already exists",
        )?;
        private_dir(&location)?;
        atomic_private(&location.join("plan.md"), plan)?;
        atomic_private(&location.join("prompt.txt"), prompt)?;
        for name in [
            "events.jsonl",
            "final.json",
            "diagnostics.txt",
            "launcher-diagnostics.txt",
            "preflight.txt",
        ] {
            atomic_private(&location.join(name), b"")?;
        }
        record["plan_hash"] = digest(plan).into();
        record["prompt_hash"] = digest(prompt).into();
        self.save(record)
    }
    pub fn save(&self, record: &Value) -> Result<()> {
        let location = self.path(string(&record["id"])?)?;
        private_stat(&location, true)?;
        let mut raw = serde_json::to_vec(record)?;
        let mut mac = Hmac::<Sha256>::new_from_slice(&self.key)?;
        mac.update(&raw);
        let signature = hex(&mac.finalize().into_bytes());
        raw.extend_from_slice(format!("\n{signature}\n").as_bytes());
        atomic_private(&location.join("record.json"), &raw)
    }
    pub fn load(&self, execution: &str) -> Result<Value> {
        let location = self.path(execution)?;
        private_stat(&location, true)?;
        let raw = private_read(&location.join("record.json"))?;
        let parts: Vec<_> = raw.split(|b| *b == b'\n').collect();
        ensure(
            parts.len() == 3 && parts[2].is_empty(),
            "private record is malformed",
        )?;
        let signature = std::str::from_utf8(parts[1])?;
        ensure(id(signature, 64), "private record authentication failed")?;
        let signature: Vec<_> = (0..64)
            .step_by(2)
            .map(|i| u8::from_str_radix(&signature[i..i + 2], 16))
            .collect::<std::result::Result<_, _>>()?;
        let mut mac = Hmac::<Sha256>::new_from_slice(&self.key)?;
        mac.update(parts[0]);
        mac.verify_slice(&signature)
            .map_err(|_| "private record authentication failed")?;
        let record = strict_json(parts[0])?;
        ensure(
            record.is_object() && record["id"] == execution && record["contract"] == CONTRACT,
            "private record identity mismatch",
        )?;
        let plan = private_read(&location.join("plan.md"))?;
        ensure(
            digest(&plan) == record["plan_hash"]
                && digest(&private_read(&location.join("prompt.txt"))?) == record["prompt_hash"],
            "private plan or prompt hash mismatch",
        )?;
        parse_plan(&plan)?;
        Ok(record)
    }
    pub fn write_artifact(&self, execution: &str, name: &str, raw: &[u8]) -> Result<()> {
        ensure(
            [
                "events.jsonl",
                "final.json",
                "diagnostics.txt",
                "launcher-diagnostics.txt",
                "preflight.txt",
                "metrics.json",
            ]
            .contains(&name),
            "invalid artifact name",
        )?;
        atomic_private(&self.path(execution)?.join(name), raw)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    #[test]
    fn authenticated_roundtrip_and_old_state_untouched() {
        let dir = tempfile::tempdir().unwrap();
        let old = dir.path().join("codex-improve-v18");
        fs::create_dir(&old).unwrap();
        fs::write(old.join("sentinel"), b"old state remains").unwrap();
        let store = StateStore::new(Some(dir.path())).unwrap();
        let plan = format!(
            "- **Improve contract**: `{CONTRACT}`\n```json codex-improve-environment\n{{\"version\":1,\"launcher\":[\"env\"],\"probes\":[]}}\n```\n```json codex-improve-routing\n{{\"version\":1,\"lane\":\"standard\",\"writePaths\":[\"*\"],\"requiredEvidence\":[]}}\n```\n```json codex-improve-gates\n{{\"version\":1,\"gates\":[]}}\n```\n"
        );
        let mut record = json!({"id":new_id().unwrap(),"contract":CONTRACT,"value":"值"});
        store
            .create(&mut record, plan.as_bytes(), b"prompt")
            .unwrap();
        let execution = record["id"].as_str().unwrap();
        let _lock = store.lock(execution).unwrap();
        assert_eq!(store.load(execution).unwrap(), record);
        let path = store.path(execution).unwrap().join("record.json");
        let mut raw = fs::read(&path).unwrap();
        raw[10] ^= 1;
        fs::write(&path, raw).unwrap();
        assert!(store.load(execution).is_err());
        assert_eq!(
            fs::read(old.join("sentinel")).unwrap(),
            b"old state remains"
        );
        fs::set_permissions(&store.cache, fs::Permissions::from_mode(0o755)).unwrap();
        assert!(StateStore::new(Some(dir.path())).is_err());
    }
}

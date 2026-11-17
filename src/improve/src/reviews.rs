use crate::{
    Result,
    contracts::*,
    ensure,
    git_worktree::{git, require_oid},
    visual::read_local,
};
use serde_json::{Value, json};
use std::{collections::BTreeSet, path::Path};

pub fn artifact_bytes(artifact: &Value) -> Result<Vec<u8>> {
    ensure(
        keys(artifact, &["path", "sha256"], &[])
            && text(&artifact["path"])
            && artifact["sha256"].as_str().is_some_and(|s| id(s, 64)),
        "invalid evidence artifact",
    )?;
    let path = std::path::absolute(string(&artifact["path"])?)?;
    let raw = read_local(
        path.parent().ok_or("missing artifact parent")?,
        path.file_name()
            .and_then(|s| s.to_str())
            .ok_or("invalid artifact name")?,
        1024 * 1024,
    )?;
    ensure(
        digest(&raw) == artifact["sha256"],
        "evidence artifact changed",
    )?;
    Ok(raw)
}
pub fn evidence(task: &Value, dossier: &Value, head: &str, tree: &str) -> Result<String> {
    ensure(
        keys(
            dossier,
            &["version", "taskId", "head", "tree", "evidence", "notes"],
            &["target"],
        ) && dossier["version"].as_u64() == Some(1)
            && dossier["taskId"] == task["id"]
            && dossier["head"] == head
            && dossier["tree"] == tree
            && text(&dossier["notes"]),
        "invalid review dossier or candidate identity",
    )?;
    let gates = array(&task["plan_settings"]["gates"])?;
    let required = array(&task["plan_settings"]["routing"]["requiredEvidence"])?;
    let mut seen = BTreeSet::new();
    for item in array(&dossier["evidence"])? {
        ensure(
            keys(
                item,
                &[
                    "gate",
                    "status",
                    "artifact",
                    "environment",
                    "head",
                    "tree",
                    "planHash",
                ],
                &[],
            ),
            "invalid gate evidence",
        )?;
        let gate_id = string(&item["gate"])?;
        ensure(seen.insert(gate_id), "duplicate gate evidence")?;
        let gate = gates
            .iter()
            .find(|g| g["id"] == gate_id)
            .ok_or("unknown gate")?;
        ensure(
            gate["kind"] == "check"
                && item["head"] == head
                && item["tree"] == tree
                && item["planHash"] == task["plan_hash"]
                && item["environment"] == gate["environment"],
            "stale or conflicting gate evidence",
        )?;
        ensure(
            member(&item["status"], &["PASS", "PENDING"])
                && (!required.contains(&item["gate"])
                    || gate["class"] != "implementation gate"
                    || item["status"] == "PASS"),
            "required implementation gate has not passed",
        )?;
        artifact_bytes(&item["artifact"])?;
    }
    ensure(
        !gates.iter().any(|g| {
            required.contains(&g["id"])
                && g["kind"] == "check"
                && !seen.contains(g["id"].as_str().unwrap_or_default())
        }),
        "missing required gate evidence",
    )?;
    if let Some(target) = dossier.get("target") {
        ensure(
            keys(target, &["worktree", "head", "mergeTree"], &[]),
            "invalid integration target",
        )?;
        let path = Path::new(string(&target["worktree"])?);
        crate::git_worktree::require_physical(path)?;
        let target_head = string(&target["head"])?;
        require_oid(path, target_head, "commit")?;
        ensure(
            git(path, &["rev-parse", "HEAD"])? == target_head && target["mergeTree"] == tree,
            "integration target drift",
        )?;
        let source = string(&task["checkpoint_oid"])?;
        require_oid(path, source, "commit")?;
        let base = git(path, &["merge-base", target_head, source])?;
        let probe = git(
            path,
            &[
                "merge-tree",
                "--write-tree",
                "--merge-base",
                &base,
                target_head,
                source,
            ],
        )?;
        ensure(
            probe.lines().next() == Some(tree),
            "merge tree requires a new independent review",
        )?;
    }
    Ok(digest(&serde_json::to_vec(dossier)?))
}
pub fn review_coverage(task: &Value, report: &Value) -> Result<()> {
    validate_review(report)?;
    let required = array(&task["plan_settings"]["routing"]["requiredEvidence"])?;
    let expected: BTreeSet<_> = std::iter::once("scope")
        .chain(required.iter().map(|v| v.as_str().unwrap_or_default()))
        .collect();
    let coverage = array(&report["coverage"])?;
    let deferred = array(&report["deferred_acceptance"])?;
    let actual: BTreeSet<_> = coverage
        .iter()
        .map(|i| string(&i["check"]))
        .collect::<Result<_>>()?;
    let later: BTreeSet<_> = deferred
        .iter()
        .map(|i| string(&i["check"]))
        .collect::<Result<_>>()?;
    let allowed: BTreeSet<_> = array(&task["plan_settings"]["gates"])?
        .iter()
        .filter(|g| g["class"] == "deferred acceptance")
        .map(|g| string(&g["id"]))
        .collect::<Result<_>>()?;
    ensure(
        actual.len() == coverage.len()
            && actual == expected
            && later.len() == deferred.len()
            && later.is_subset(&allowed)
            && actual.is_disjoint(&later),
        "review lacks exact required coverage",
    )?;
    ensure(
        array(&report["findings"])?
            .iter()
            .all(|f| expected.contains(f["check"].as_str().unwrap_or_default())),
        "finding refers to unknown check",
    )
}
pub fn binding(
    task: &Value,
    head: &str,
    tree: &str,
    method: &str,
    evidence: &str,
    reviewer: &Value,
) -> Value {
    json!({"task":task["id"],"plan":task["plan_hash"],"settings":task["settings"],"implementation":task["implementation"],"grants":task["grants"],"worktree":task["worktree"],"common_dir":task["common_dir"],"base":task["base_head"],"head":head,"tree":tree,"method":method,"reviewer":reviewer,"evidence":evidence,"images":task["images"]})
}
pub fn require_approval(task: &Value, current: &Value) -> Result<()> {
    let review = &task["review"];
    ensure(
        review["outcome"] == "APPROVE"
            && review["binding"] == *current
            && review["id"] == task["approval"],
        "missing or stale independent approval",
    )?;
    review_coverage(task, &review["report"])?;
    ensure(
        review["report"]["verdict"] == "APPROVE",
        "review did not approve",
    )
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_coverage_and_policy_binding() {
        let mut task = json!({"id":"task","settings":{"budget":300000},"plan_settings":{"routing":{"requiredEvidence":["G1"]},"gates":[{"id":"G1","class":"implementation gate"}]}});
        let mut report = json!({"verdict":"APPROVE","summary":"checked","findings":[],"coverage":[{"check":"scope","status":"PASS","evidence":"read"},{"check":"G1","status":"PASS","evidence":"tested"}],"review_blockers":[],"deferred_acceptance":[]});
        review_coverage(&task, &report).unwrap();
        let reviewer = json!({"model":"actual","sandbox":{"type":"readOnly"}});
        let b = binding(&task, "head", "tree", "method", "evidence", &reviewer);
        task["review"] = json!({"id":"review","outcome":"APPROVE","report":report,"binding":b});
        task["approval"] = json!("review");
        require_approval(&task, &b).unwrap();
        for (field, value) in [
            ("plan_hash", json!("new")),
            ("settings", json!({})),
            ("images", json!(["new"])),
        ] {
            let mut changed = task.clone();
            changed[field] = value;
            assert!(
                require_approval(
                    &changed,
                    &binding(&changed, "head", "tree", "method", "evidence", &reviewer)
                )
                .is_err()
            );
        }
        for (head, tree, method, evidence) in [
            ("new", "tree", "method", "evidence"),
            ("head", "new", "method", "evidence"),
            ("head", "tree", "new", "evidence"),
            ("head", "tree", "method", "new"),
        ] {
            assert!(
                require_approval(
                    &task,
                    &binding(&task, head, tree, method, evidence, &reviewer)
                )
                .is_err()
            );
        }
        let duplicate = report["coverage"][0].clone();
        report["coverage"].as_array_mut().unwrap().push(duplicate);
        assert!(review_coverage(&task, &report).is_err());
        task["review"]["outcome"] = json!("unknown");
        assert!(require_approval(&task, &b).is_err());
    }
    #[test]
    fn evidence_checks_artifact_bytes_and_exact_target() {
        let temp = tempfile::tempdir().unwrap();
        let repo = temp.path();
        for args in [
            vec!["init", "-q"],
            vec!["config", "user.name", "Fixture"],
            vec!["config", "user.email", "fixture@example.invalid"],
            vec!["commit", "--allow-empty", "-qm", "test: target"],
        ] {
            git(repo, &args).unwrap();
        }
        let head = git(repo, &["rev-parse", "HEAD"]).unwrap();
        let tree = git(repo, &["rev-parse", "HEAD^{tree}"]).unwrap();
        let artifact = repo.join("gate.log");
        std::fs::write(&artifact, "passed").unwrap();
        let task = json!({"id":"task","plan_hash":digest(b"plan"),"checkpoint_oid":head,
            "plan_settings":{"routing":{"requiredEvidence":["G1"]},"gates":[
                {"id":"G1","kind":"check","class":"implementation gate","environment":"fixture"}]}});
        let dossier = json!({"version":1,"taskId":"task","head":head,"tree":tree,"notes":"checked",
            "evidence":[{"gate":"G1","status":"PASS","head":head,"tree":tree,"planHash":task["plan_hash"],
                "environment":"fixture","artifact":{"path":artifact,"sha256":digest(b"passed")}}],
            "target":{"worktree":repo,"head":head,"mergeTree":tree}});
        evidence(&task, &dossier, &head, &tree).unwrap();
        for (field, value) in [
            ("status", json!("PENDING")),
            ("planHash", json!(digest(b"changed"))),
        ] {
            let mut changed = dossier.clone();
            changed["evidence"][0][field] = value;
            assert!(evidence(&task, &changed, &head, &tree).is_err());
        }
        let mut changed = dossier.clone();
        changed["target"]["mergeTree"] = json!("0".repeat(tree.len()));
        assert!(evidence(&task, &changed, &head, &tree).is_err());
        std::fs::write(&artifact, "changed").unwrap();
        assert!(evidence(&task, &dossier, &head, &tree).is_err());
        std::fs::write(&artifact, "passed").unwrap();
        git(
            repo,
            &["commit", "--allow-empty", "-qm", "test: target drift"],
        )
        .unwrap();
        assert!(evidence(&task, &dossier, &head, &tree).is_err());
    }
}

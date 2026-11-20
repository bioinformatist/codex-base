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
pub fn review_checks(task: &Value) -> Result<(BTreeSet<&str>, BTreeSet<&str>)> {
    let required = array(&task["plan_settings"]["routing"]["requiredEvidence"])?;
    let expected = std::iter::once(Ok("scope"))
        .chain(required.iter().map(string))
        .collect::<Result<_>>()?;
    let allowed = array(&task["plan_settings"]["gates"])?
        .iter()
        .filter(|g| g["class"] == "deferred acceptance")
        .map(|g| string(&g["id"]))
        .collect::<Result<_>>()?;
    Ok((expected, allowed))
}
pub fn review_schema(task: &Value, mut schema: Value) -> Result<Value> {
    let (expected, allowed) = review_checks(task)?;
    let properties = &mut schema["properties"];
    for field in ["coverage", "findings"] {
        properties[field]["items"]["properties"]["check"]["enum"] = json!(expected);
    }
    properties["coverage"]["minItems"] = json!(expected.len());
    properties["coverage"]["maxItems"] = json!(expected.len());
    properties["deferred_acceptance"]["maxItems"] = json!(allowed.len());
    if !allowed.is_empty() {
        properties["deferred_acceptance"]["items"]["properties"]["check"]["enum"] = json!(allowed);
    }
    Ok(schema)
}
pub fn review_coverage(task: &Value, report: &Value) -> Result<()> {
    let (expected, allowed) = review_checks(task)?;
    let mut actual = BTreeSet::new();
    for item in array(&report["coverage"])? {
        let check = string(&item["check"])?;
        ensure(
            expected.contains(check),
            format!("unknown coverage check: {check}"),
        )?;
        ensure(
            actual.insert(check),
            format!("duplicate coverage check: {check}"),
        )?;
    }
    let missing: Vec<_> = expected.difference(&actual).copied().collect();
    ensure(
        missing.is_empty(),
        format!("missing coverage checks: {}", missing.join(", ")),
    )?;
    let mut later = BTreeSet::new();
    for item in array(&report["deferred_acceptance"])? {
        let check = string(&item["check"])?;
        ensure(
            !actual.contains(check),
            format!("check in both coverage and deferred_acceptance: {check}"),
        )?;
        ensure(
            allowed.contains(check),
            format!("undeclared deferred_acceptance check: {check}"),
        )?;
        ensure(
            later.insert(check),
            format!("duplicate deferred_acceptance check: {check}"),
        )?;
    }
    for item in array(&report["findings"])? {
        let check = string(&item["check"])?;
        ensure(
            expected.contains(check),
            format!("unknown findings check: {check}"),
        )?;
    }
    validate_review(report)
}
pub fn require_reviewable(task: &Value) -> Result<()> {
    ensure(
        task["review"]["outcome"] != "running"
            && (task["outcome"] == "COMPLETE" && task["nativeStatus"] == "completed"
                || member(&task["nativeStatus"], &["failed", "interrupted"])
                    && member(
                        &task["outcome"],
                        &["budget_exhausted", "timed_out", "cancelled", "failed"],
                    )
                    && task["report"]["status"] != "STOPPED"),
        "review requires COMPLETE or a confirmed failed/interrupted implementation, and no active review",
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
            && review["nativeStatus"] == "completed"
            && review["nativeError"].is_null()
            && review["reportError"].is_null()
            && review["coverageError"].is_null()
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
    fn review_check_ids_have_specific_diagnostics() {
        let mut task = json!({"plan_settings":{"routing":{"requiredEvidence":["G1","G2","G3","G4","G5"]},"gates":[]}});
        let expected = json!(["G1", "G2", "G3", "G4", "G5", "scope"]);
        let report = json!({"verdict":"APPROVE","summary":"checked","findings":[],
            "coverage":expected.as_array().unwrap().iter().map(|check|json!({"check":check,"status":"PASS","evidence":"read"})).collect::<Vec<_>>(),
            "review_blockers":[],"deferred_acceptance":[]});
        review_coverage(&task, &report).unwrap();
        let mut empty = report.clone();
        empty["coverage"] = json!([]);
        assert_eq!(
            review_coverage(&task, &empty).unwrap_err().to_string(),
            "missing coverage checks: G1, G2, G3, G4, G5, scope"
        );
        for (field, entries, diagnostic) in [
            (
                "coverage",
                json!([
                    report["coverage"][0],
                    report["coverage"][2],
                    report["coverage"][3],
                    report["coverage"][4],
                    report["coverage"][5]
                ]),
                "missing coverage checks: G2",
            ),
            (
                "coverage",
                json!([report["coverage"][1], report["coverage"][1]]),
                "duplicate coverage check: G2",
            ),
            (
                "coverage",
                json!([{"check":"G6","status":"PASS","evidence":"read"}]),
                "unknown coverage check: G6",
            ),
            (
                "deferred_acceptance",
                json!([{"check":"G2","owner":"host","reason":"later","evidence_required":"pass"}]),
                "check in both coverage and deferred_acceptance: G2",
            ),
            (
                "deferred_acceptance",
                json!([{"check":"D-CI","owner":"host","reason":"later","evidence_required":"pass"}]),
                "undeclared deferred_acceptance check: D-CI",
            ),
        ] {
            let mut changed = report.clone();
            changed[field] = entries;
            assert_eq!(
                review_coverage(&task, &changed).unwrap_err().to_string(),
                diagnostic
            );
        }
        let mut finding = report.clone();
        finding["verdict"] = json!("REVISE");
        finding["coverage"][0]["status"] = json!("FAIL");
        finding["findings"] = json!([{"check":"G6","severity":"medium","location":"code:1","claim":"wrong","evidence":"read","action":"fix"}]);
        assert_eq!(
            review_coverage(&task, &finding).unwrap_err().to_string(),
            "unknown findings check: G6"
        );
        task["plan_settings"]["gates"] = json!([{"id":"D-CI","class":"deferred acceptance"}]);
        let mut deferred = report.clone();
        deferred["deferred_acceptance"] =
            json!([{"check":"D-CI","owner":"host","reason":"later","evidence_required":"pass"}]);
        review_coverage(&task, &deferred).unwrap();
        let duplicate = deferred["deferred_acceptance"][0].clone();
        deferred["deferred_acceptance"]
            .as_array_mut()
            .unwrap()
            .push(duplicate);
        assert_eq!(
            review_coverage(&task, &deferred).unwrap_err().to_string(),
            "duplicate deferred_acceptance check: D-CI"
        );
    }
    #[test]
    fn interrupted_review_requires_confirmed_native_failure() {
        let mut task = json!({"outcome":"COMPLETE","nativeStatus":"completed"});
        require_reviewable(&task).unwrap();
        for (status, result, allowed) in [
            ("failed", "budget_exhausted", true),
            ("failed", "timed_out", true),
            ("interrupted", "cancelled", true),
            ("failed", "failed", true),
            ("unknown", "budget_exhausted", false),
            ("inProgress", "running", false),
            ("completed", "invalid_output", false),
            ("completed", "STOPPED", false),
            ("completed", "cancelled", false),
        ] {
            task["nativeStatus"] = status.into();
            task["outcome"] = result.into();
            assert_eq!(
                require_reviewable(&task).is_ok(),
                allowed,
                "{status}/{result}"
            );
        }
        task["nativeStatus"] = "interrupted".into();
        task["outcome"] = "cancelled".into();
        task["report"] = json!({"status":"STOPPED"});
        assert!(require_reviewable(&task).is_err());
        task["report"] = Value::Null;
        task["review"] = json!({"outcome":"running"});
        assert!(require_reviewable(&task).is_err());
    }
    #[test]
    fn exact_coverage_and_policy_binding() {
        let mut task = json!({"id":"task","settings":{"budget":300000},"plan_settings":{"routing":{"requiredEvidence":["G1"]},"gates":[{"id":"G1","class":"implementation gate"}]}});
        let mut report = json!({"verdict":"APPROVE","summary":"checked","findings":[],"coverage":[{"check":"scope","status":"PASS","evidence":"read"},{"check":"G1","status":"PASS","evidence":"tested"}],"review_blockers":[],"deferred_acceptance":[]});
        review_coverage(&task, &report).unwrap();
        let reviewer = json!({"model":"actual","sandbox":{"type":"readOnly"}});
        let b = binding(&task, "head", "tree", "method", "evidence", &reviewer);
        task["review"] = json!({"id":"review","outcome":"APPROVE","nativeStatus":"completed","report":report,"binding":b});
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
        task["review"]["outcome"] = json!("APPROVE");
        task["review"]["nativeStatus"] = json!("failed");
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

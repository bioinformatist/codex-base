use crate::{
    Result,
    contracts::*,
    ensure,
    git_worktree::{git, require_oid},
    state::*,
    visual::{image_paths, read_local},
};
use serde_json::{Value, json};
use std::{collections::BTreeSet, path::Path};

fn artifact_bytes(artifact: &Value) -> Result<Vec<u8>> {
    ensure(
        keys(artifact, &["path", "sha256"], &[]) && text(&artifact["path"]),
        "gate requires a real artifact reference",
    )?;
    let path = std::path::absolute(string(&artifact["path"])?)?;
    read_local(
        path.parent().ok_or("missing artifact parent")?,
        path.file_name()
            .ok_or("missing artifact name")?
            .to_str()
            .ok_or("non-UTF8 artifact")?,
        1024 * 1024,
    )
}
pub fn evidence(
    store: &StateStore,
    execution: &Value,
    dossier: &Value,
    head: &str,
    tree: &str,
) -> Result<Value> {
    ensure(
        keys(
            dossier,
            &[
                "version",
                "executionId",
                "head",
                "tree",
                "evidence",
                "notes",
            ],
            &["target"],
        ) && dossier["version"].as_u64() == Some(1),
        "invalid structured review dossier",
    )?;
    ensure(
        dossier["executionId"] == execution["id"]
            && dossier["head"] == head
            && dossier["tree"] == tree
            && text(&dossier["notes"]),
        "review dossier execution or candidate mismatch",
    )?;
    let entries = array(&dossier["evidence"])?;
    let gates = array(&execution["plan_settings"]["gates"])?;
    let required = array(&execution["plan_settings"]["routing"]["requiredEvidence"])?;
    let mut seen = BTreeSet::new();
    let mut visuals = Vec::new();
    for item in entries {
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
                &["visualExecutionId"],
            ),
            "invalid gate evidence",
        )?;
        let gate_id = string(&item["gate"])?;
        ensure(seen.insert(gate_id), "duplicate gate evidence")?;
        let gate = gates
            .iter()
            .find(|g| g["id"] == gate_id)
            .ok_or("unknown gate evidence")?;
        ensure(
            gate["kind"] == "check"
                && item["head"] == head
                && item["tree"] == tree
                && item["planHash"] == execution["plan_hash"]
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
        let raw = artifact_bytes(&item["artifact"])?;
        ensure(
            digest(&raw) == item["artifact"]["sha256"],
            "gate evidence digest mismatch",
        )?;
        if let Some(id) = item.get("visualExecutionId") {
            let visual = store.load(string(id)?)?;
            let images = array(&visual["images"])?;
            ensure(
                visual["kind"] == "visual"
                    && visual["outcome"] == "COMPLETE"
                    && visual["base_head"] == head
                    && visual["candidate_tree"] == tree
                    && images
                        .iter()
                        .any(|i| i["purpose"] == "candidate" && i["bound"] == true)
                    && !images
                        .iter()
                        .any(|i| i["purpose"] == "candidate" && i["bound"] != true),
                "visual evidence is unbound or stale",
            )?;
            ensure(
                digest(&private_read(
                    &store.path(string(&visual["id"])?)?.join("final.json"),
                )?) == visual["final_hash"]
                    && digest(&raw) == visual["final_hash"],
                "visual gate must reference the actual visual report",
            )?;
            image_paths(store, &visual)?;
            visuals.push(visual);
        }
    }
    ensure(
        !gates.iter().any(|g| {
            required.contains(&g["id"])
                && g["kind"] == "check"
                && !seen.contains(g["id"].as_str().unwrap_or_default())
        }),
        "missing required gate evidence",
    )?;
    if let Some(target) = dossier.get("target").filter(|v| !v.is_null()) {
        ensure(
            keys(target, &["worktree", "head", "mergeTree"], &[]),
            "invalid integration target binding",
        )?;
        let path = Path::new(string(&target["worktree"])?).canonicalize()?;
        let target_head = string(&target["head"])?;
        require_oid(&path, target_head, "commit")?;
        require_oid(&path, string(&target["mergeTree"])?, "tree")?;
        ensure(
            git(&path, &["rev-parse", "HEAD"])? == target_head && target["mergeTree"] == tree,
            "target drift or new merge candidate requires independent preparation and review",
        )?;
        let source = execution["checkpoint_oid"]
            .as_str()
            .ok_or("integration review requires the authenticated checkpoint")?;
        let base = git(&path, &["merge-base", target_head, source])?;
        let probe = git(
            &path,
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
            "precomputed merge tree differs; prepare a new merge candidate independently",
        )?;
    }
    Ok(json!({"dossier":dossier,"digest":digest(&serde_json::to_vec(dossier)?),"visuals":visuals}))
}
pub fn review_coverage(execution: &Value, report: &Value) -> Result<()> {
    validate_review(report)?;
    let required = array(&execution["plan_settings"]["routing"]["requiredEvidence"])?;
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
    let allowed: BTreeSet<_> = array(&execution["plan_settings"]["gates"])?
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
        "review lacks exact required coverage or has unknown/duplicate checks",
    )?;
    ensure(
        array(&report["findings"])?
            .iter()
            .all(|f| expected.contains(f["check"].as_str().unwrap_or_default())),
        "finding refers to an unknown check",
    )
}
pub fn binding(
    execution: &Value,
    head: &str,
    tree: &str,
    method_hash: &str,
    verified: &Value,
    reviewer: &Value,
) -> Result<Value> {
    let visuals: Vec<_> = array(&verified["visuals"])?
        .iter()
        .map(|v| json!({"id":v["id"],"images":v["images"],"report":v["report"]}))
        .collect();
    Ok(
        json!({"execution":execution["id"],"lineage":execution["lineage"],"plan":execution["plan_hash"],"role":execution["role_settings"],"grants":execution["grants"],"worktree":execution["worktree"],"head":head,"tree":tree,"method":method_hash,"reviewer":reviewer,"evidence":verified["digest"],"environment":execution["environment_settings"],"images":execution.get("images").cloned().unwrap_or(json!([])),"visualReport":execution["visual_report"],"visualEvidence":visuals}),
    )
}
pub fn reconciliation_evidence(dossier: &Value) -> Result<()> {
    let mut supports: Vec<&Value> = array(&dossier["evidence"])?.iter().collect();
    for finding in array(&dossier["findings"])? {
        supports.extend(array(&finding["evidence"])?);
    }
    ensure(
        !supports.is_empty(),
        "reconciliation requires supporting evidence",
    )?;
    for artifact in supports {
        ensure(
            digest(&artifact_bytes(artifact)?) == artifact["sha256"],
            "reconciliation evidence digest mismatch",
        )?;
    }
    Ok(())
}
pub fn approve(
    store: &StateStore,
    execution: &mut Value,
    review: &Value,
    source: &str,
) -> Result<()> {
    ensure(
        store.load(string(&execution["lineage"])?)?["last_review"] == review["id"],
        "approval requires the latest review",
    )?;
    if source == "reconciliation" {
        reconciliation_evidence(&review["reconciliation"])?;
    }
    execution["approval"] =
        json!({"reviewId":review["id"],"binding":review["review_binding"],"source":source});
    store.save(execution)
}
pub fn require_approval(
    store: &StateStore,
    execution: &Value,
    head: &str,
    tree: &str,
    method_hash: &str,
    reviewer: &Value,
) -> Result<Value> {
    let approval = &execution["approval"];
    ensure(
        approval.is_object()
            && store.load(string(&execution["lineage"])?)?["last_review"] == approval["reviewId"],
        "checkpoint requires matching latest authenticated review approval",
    )?;
    let review = store.load(string(&approval["reviewId"])?)?;
    let dossier = strict_json(&private_read(
        &store.path(string(&review["id"])?)?.join("dossier.json"),
    )?)?;
    let verified = evidence(store, execution, &dossier, head, tree)?;
    ensure(
        binding(execution, head, tree, method_hash, &verified, reviewer)? == approval["binding"],
        "review approval is stale",
    )?;
    if approval["source"] == "reconciliation" {
        reconciliation_evidence(&review["reconciliation"])?;
    }
    Ok(review)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn exact_coverage_and_binding_include_reviewer_and_evidence() {
        let execution = json!({"id":"execution","lineage":"execution","plan_hash":"plan","role_settings":{"model":"executor"},"grants":[],"worktree":"worktree","environment_settings":{},"plan_settings":{"routing":{"requiredEvidence":["G1"]},"gates":[{"id":"G1","class":"implementation gate"},{"id":"G5","class":"deferred acceptance"}]}});
        let mut report = json!({"verdict":"APPROVE","summary":"checked","findings":[],"coverage":[{"check":"scope","status":"PASS","evidence":"reviewed"},{"check":"G1","status":"PASS","evidence":"checked"}],"review_blockers":[],"deferred_acceptance":[{"check":"G5","owner":"maintainer","reason":"CI","evidence_required":"passing run"}]});
        review_coverage(&execution, &report).unwrap();
        let duplicate = report["coverage"][0].clone();
        report["coverage"].as_array_mut().unwrap().push(duplicate);
        assert!(review_coverage(&execution, &report).is_err());
        let verified = json!({"digest":"artifact","visuals":[]});
        let a = binding(
            &execution,
            "head",
            "tree",
            "method",
            &verified,
            &json!({"model":"reviewer"}),
        )
        .unwrap();
        let b = binding(
            &execution,
            "head",
            "tree",
            "method",
            &verified,
            &json!({"model":"changed"}),
        )
        .unwrap();
        assert_ne!(a, b);
        assert_eq!(a["evidence"], "artifact");
    }
}

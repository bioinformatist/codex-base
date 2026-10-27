"""Execution-bound review evidence and approvals in the existing authenticated store."""
from __future__ import annotations

import json
from pathlib import Path

from contracts import (BoundaryError, digest, private_read, strict_json, validate_review,
                       _text)
from git_worktree import command, git, require_oid
from visual import image_paths, read_local


def evidence(store, execution: dict, dossier: dict, head: str, tree: str) -> dict:
    if not isinstance(dossier, dict) or not {"version", "executionId", "head", "tree", "evidence", "notes"} <= set(dossier) or not set(dossier) <= {"version", "executionId", "head", "tree", "evidence", "notes", "target"} or type(dossier["version"]) is not int or dossier["version"] != 1:
        raise BoundaryError("invalid structured review dossier")
    if (dossier["executionId"], dossier["head"], dossier["tree"]) != (execution["id"], head, tree) or not _text(dossier["notes"]):
        raise BoundaryError("review dossier execution or candidate mismatch")
    entries = dossier["evidence"]
    if not isinstance(entries, list):
        raise BoundaryError("review evidence must be an array")
    gates = {gate["id"]:gate for gate in execution["plan_settings"]["gates"]}
    required = execution["plan_settings"]["routing"]["requiredEvidence"]
    seen = set()
    visuals = []
    for item in entries:
        if not isinstance(item, dict) or not {"gate", "status", "artifact", "environment", "head", "tree", "planHash"} <= set(item) or not set(item) <= {"gate", "status", "artifact", "environment", "head", "tree", "planHash", "visualExecutionId"}:
            raise BoundaryError("invalid gate evidence")
        gate_id = item["gate"]
        if not isinstance(gate_id, str) or gate_id in seen or gate_id not in gates:
            raise BoundaryError("duplicate or unknown gate evidence")
        seen.add(gate_id)
        gate = gates[gate_id]
        if gate["kind"] != "check" or (item["head"], item["tree"], item["planHash"], item["environment"]) != (head, tree, execution["plan_hash"], gate["environment"]):
            raise BoundaryError("stale or conflicting gate evidence")
        if item["status"] not in ("PASS", "PENDING") or (gate_id in required and gate["class"] == "implementation gate" and item["status"] != "PASS"):
            raise BoundaryError("required implementation gate has not passed")
        artifact = item["artifact"]
        if not isinstance(artifact, dict) or set(artifact) != {"path", "sha256"} or not _text(artifact["path"]):
            raise BoundaryError("gate requires a real artifact reference")
        path = Path(artifact["path"]).absolute()
        raw = read_local(path.parent, path.name, 1024 * 1024)
        if digest(raw) != artifact["sha256"]:
            raise BoundaryError("gate evidence digest mismatch")
        if "visualExecutionId" in item:
            visual = store.load(item["visualExecutionId"])
            if visual["kind"] != "visual" or visual["outcome"] != "COMPLETE" or (visual["base_head"], visual["candidate_tree"]) != (head, tree) or not any(image["purpose"] == "candidate" and image["bound"] for image in visual.get("images", [])) or any(image["purpose"] == "candidate" and not image["bound"] for image in visual.get("images", [])):
                raise BoundaryError("visual evidence is unbound or stale")
            if digest(private_read(store.path(visual["id"]) / "final.json")) != visual.get("final_hash") or digest(raw) != visual["final_hash"]:
                raise BoundaryError("visual gate must reference the actual visual report")
            image_paths(store, visual)
            visuals.append(visual)
    if any(gates[key]["kind"] == "check" and key not in seen for key in required):
        raise BoundaryError("missing required gate evidence")
    target = dossier.get("target")
    if target is not None:
        if not isinstance(target, dict) or set(target) != {"worktree", "head", "mergeTree"}:
            raise BoundaryError("invalid integration target binding")
        path = Path(target["worktree"]).resolve(strict=True)
        require_oid(path, target["head"], "commit")
        require_oid(path, target["mergeTree"], "tree")
        if git(path,"rev-parse","HEAD") != target["head"] or target["mergeTree"] != tree:
            raise BoundaryError("target drift or new merge candidate requires independent preparation and review")
        source_oid = execution.get("checkpoint_oid")
        if not source_oid:
            raise BoundaryError("integration review requires the authenticated checkpoint")
        base = git(path,"merge-base",target["head"],source_oid)
        probe = command(["git","-C",str(path),"merge-tree","--write-tree","--merge-base",base,target["head"],source_oid],check=False)
        if probe.returncode or probe.stdout.splitlines()[0] != tree:
            raise BoundaryError("precomputed merge tree differs; prepare a new merge candidate independently")
    return {"dossier":dossier, "digest":digest(json.dumps(dossier,sort_keys=True).encode()),
            "visuals":visuals}


def review_coverage(execution: dict, report: dict) -> None:
    validate_review(report)
    expected = {"scope", *execution["plan_settings"]["routing"]["requiredEvidence"]}
    coverage = [item["check"] for item in report["coverage"]]
    deferred = [item["check"] for item in report["deferred_acceptance"]]
    allowed_deferred = {gate["id"] for gate in execution["plan_settings"]["gates"] if gate["class"] == "deferred acceptance"}
    if len(coverage) != len(set(coverage)) or set(coverage) != expected or len(deferred) != len(set(deferred)) or not set(deferred) <= allowed_deferred or set(coverage) & set(deferred):
        raise BoundaryError("review lacks exact required coverage or has unknown/duplicate checks")
    if any(finding["check"] not in expected for finding in report["findings"]):
        raise BoundaryError("finding refers to an unknown check")


def binding(execution: dict, head: str, tree: str, method_hash: str, verified: dict,
            reviewer_settings: dict) -> dict:
    return {"execution":execution["id"], "lineage":execution["lineage"],
            "plan":execution["plan_hash"], "role":execution["role_settings"],
            "grants":execution["grants"], "worktree":execution["worktree"],
            "head":head,"tree":tree,"method":method_hash,"reviewer":reviewer_settings,
            "evidence":verified["digest"],
            "environment":execution["environment_settings"],
            "images":execution.get("images",[]),"visualReport":execution.get("visual_report"),
            "visualEvidence":[{"id":v["id"],"images":v["images"],"report":v["report"]} for v in verified["visuals"]]}


def reconciliation_evidence(dossier: dict) -> None:
    supports = [*dossier["evidence"]]
    for finding in dossier["findings"]:
        supports.extend(finding["evidence"])
    if not supports:
        raise BoundaryError("reconciliation requires supporting evidence")
    for artifact in supports:
        if not isinstance(artifact, dict) or set(artifact) != {"path", "sha256"}:
            raise BoundaryError("invalid reconciliation artifact")
        path = Path(artifact["path"]).absolute()
        if digest(read_local(path.parent, path.name, 1024 * 1024)) != artifact["sha256"]:
            raise BoundaryError("reconciliation evidence digest mismatch")


def approve(store, execution: dict, review: dict, *, source: str = "model") -> None:
    if store.load(execution["lineage"]).get("last_review") != review["id"]:
        raise BoundaryError("approval requires the latest review")
    if source == "reconciliation":
        reconciliation_evidence(review["reconciliation"])
    execution["approval"] = {"reviewId":review["id"], "binding":review["review_binding"], "source":source}
    store.save(execution)


def require_approval(store, execution: dict, head: str, tree: str, method_hash: str,
                     reviewer_settings: dict) -> dict:
    approval = execution.get("approval")
    if not approval or store.load(execution["lineage"]).get("last_review") != approval["reviewId"]:
        raise BoundaryError("checkpoint requires matching latest authenticated review approval")
    review = store.load(approval["reviewId"])
    dossier = strict_json(private_read(store.path(review["id"]) / "dossier.json"))
    verified = evidence(store, execution, dossier, head, tree)
    if binding(execution,head,tree,method_hash,verified,reviewer_settings) != approval["binding"]:
        raise BoundaryError("review approval is stale")
    if approval["source"] == "reconciliation":
        reconciliation_evidence(review["reconciliation"])
    return review

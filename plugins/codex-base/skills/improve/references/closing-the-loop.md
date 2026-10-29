# Closing The Loop

Audit and formal planning remain read-only. After the user authorizes a reviewed
plan, the main agent saves it and delegates implementation through the public
`codex-improve` coordinator. Read the planning contract for plan, environment,
role, gate-ledger, and lifecycle requirements. The current source runtime accepts
only `1.0.0-codex.19`; older private execution state is retained separately and
is never migrated.

## Execute an approved plan

Before dispatch, verify the plan's status, semantic anchors, Engineering
contract, scope, STOP conditions, environment, lane evidence, base commit, and
required checks against the live repository. Reconcile drift with the user
before execution. Obtain explicit authority for metadata grants or external
effects; a plan alone does not grant them. `--grant .agents` and `--grant .codex`
are repeatable on the operations that accept them. `.git` is never grantable.
An optional `--copy-from SOURCE --include PATH` copies only named ignored
cache files from a validated source; the source and include set must be reviewed.

```console
codex-improve execute PLAN REPOSITORY --lane economy|standard|deep|writer
codex-improve status [EXECUTION_ID]
codex-improve candidate WORKTREE
```

The coordinator reads the one `.19` environment block in the plan, creates an
isolated Worktrunk worktree from a committed base, snapshots the plan and role,
runs the literal launcher and bounded probes, then launches official `codex exec`
with the selected role. The caller may specify a full committed `--base OID`.
Worktrunk's automation hooks and LLM commits are disabled; the later reviewed
Git checkpoint runs native Git hooks. The caller supplies host Codex, Worktrunk,
Git, Worktrunk, and the native Codex Base runtime for a portable install; Nix packages the runtime
closure. The coordinator does not download dependencies or infer a project
launcher. The native worker starts from the current executable and uses installed skill resources.

`execute`, `scout`, and `review` return a structured JSON record. Preserve its
execution ID, worktree, base HEAD, role, outcome, reason, candidate tree, report,
and artifact paths. `status` reads authenticated private state without a model
call. `candidate` reports the current full HEAD and Git tree of staged,
unstaged, deleted, mode, and nonignored untracked changes without altering the
real index. A missing or stale candidate blocks review. The executor never
calculates or reconstructs plan or candidate identity and never calls
`candidate`, `checkpoint`, or `resume`.

A preflight-only failure may use `codex-improve resume EXECUTION_ID` once after
correcting the environment. It preserves the authenticated candidate, role,
grants, and launcher. A repeated failure is blocked. Inspect diagnostics rather
than guessing from the final status; launcher and Codex diagnostics are separate.
An `INCONCLUSIVE` outcome retains its exact reason and is never silently
converted to success. Model or entitlement failures do not trigger fallback,
replay, or provider changes. Preserve the worktree and artifacts on a stop.

## Stepwise executor checkpoint

After each code or test changing step, run that step's named verification first.
Then apply the Ponytail implementation method to its new candidate delta.
Preserve accepted semantics and tests; rerun the step check and any invalidated earlier check, and
record `ponytail=lean` or `ponytail=simplified` in the step report. A finding
that challenges a settled requirement is a STOP, not authority to weaken it.
This in-process checkpoint does not require another agent or an additional
policy file. Documentation-only, read-only, and pure verification steps are
exempt. Execute every check the plan requires even when a role's default style
would otherwise omit tests.

For bounded research, report a `Research checkpoint:` in ordinary progress
messages after a named question is supported, rejected, or reaches its limit.
Include Question, Finding and certainty, exact Evidence pointer, and Next.
The final JSON report still uses the executor schema. Treat interim findings
as leads for selective verification, not as proof of an unrun check.

For selected proof work or an existing project proof contract, preserve agreed
properties and their imports to the delivered implementation. The executor
must not weaken laws, bypass imports, or downgrade a gate to obtain a pass.
Use the existing STOP/report and explicit plan-revision path for failed proofs,
counterexamples, missing tools, or exhausted task budgets.

## Recover or revise an exact candidate

When an initial execution is `INCONCLUSIVE`, `closeout_eligible` only permits
main-agent reconciliation; it is not approval for another model call. Verify
the private plan, candidate, diff, transport artifacts, and gate ledger. If the
result can be assessed completely, record an honest implementation outcome. If
it cannot, one bounded serial recovery may run under the existing implementation
authorization only when the initial reason is `rollout_budget_exhausted` or
`absolute_timeout`. Any other inconclusive initial reason, or an inconclusive
revision or review, requires explicit user approval before another model call.
An explicitly approved recovery remains possible for another initial reason.
Use one to three concrete `Scope:` slice dossiers; each slice is bounded to the
accepted plan and its candidate, and a failure ends the sequence. Recovery and
revision retain the original role, permissions, and provenance.

```console
codex-improve recover EXECUTION_ID SLICE.md [NEXT-SLICE.md ...] --expected-tree FULL_TREE
codex-improve revise EXECUTION_ID FINDINGS.md --expected-tree FULL_TREE
```

Restate the exact approved `--grant` set on these commands. Recovery is allowed
once per eligible lineage. Revision requires a concrete `Finding:` dossier,
a `COMPLETE` parent, and at most two rounds. The expected tree must match both
the captured output and the current complete worktree; drift, changed lineage,
missing original provenance, a new Engineering contract, or scope expansion is
a STOP. Never ask the executor to edit the plan or index, use coordinator
lifecycle verbs, launch agents, or silently redesign the approach. A new
candidate invalidates mapped gate and review evidence according to the plan's
ledger. Run all invalidated gates before another approval.

## Review the candidate

Capture `codex-improve candidate WORKTREE` after each implementation or
revision. Inspect the complete candidate diff and step results. A reviewer
must independently inspect the candidate code for each assigned check, then
expand where concrete gaps or contradictions appear. Do not limit inspection
to gaps claimed by an executor handoff. Review uses the completed execution ID
and a structured JSON dossier; scout uses a worktree and a read-only text
dossier. Pass the full expected tree:

```console
codex-improve review EXECUTION_ID FULL_TREE REVIEW.json
codex-improve scout WORKTREE FULL_TREE DOSSIER.md
```

### Review dossier

Read the original execution record and its plan gates. For a plan whose required
check gate is `G1`, the minimal review dossier is:

```json
{
  "version": 1, "executionId": "EXECUTION_ID", "head": "HEAD", "tree": "FULL_TREE",
  "evidence": [{
    "gate": "G1", "status": "PASS",
    "artifact": {"path": "/private/evidence/g1.log", "sha256": "ARTIFACT_SHA256"},
    "environment": "G1_ENVIRONMENT",
    "head": "HEAD", "tree": "FULL_TREE", "planHash": "PLAN_HASH"
  }],
  "notes": "Review the complete candidate against the original plan and G1 evidence."
}
```

Replace placeholders with the execution's `id`, current captured HEAD/tree and
`plan_hash`; use the exact `environment` string from the original gate. Each
artifact must be a real, unchanged file with its byte SHA256 (for example, from
`sha256sum`); use absolute paths in private dossiers. Include every required
`kind: check` gate exactly once. Review gates receive reviewer coverage rather
than artifact entries. Unknown or duplicate gates fail. Required implementation
gates must be `PASS`; `PENDING` cannot satisfy them. Notes must be nonempty.
The coordinator validates these fields against the declared gates and candidate.

### Visual inputs and evidence

Use `codex-improve visual WORKTREE FULL_TREE VISUAL.md --inputs inputs.json`.
`VISUAL.md` is a `.19` plan with the contract, environment, routing and gates
blocks from the [plan template](plan-template.md). Set its lane to `visual`,
`writePaths` to `[]`, and declare the inspection and its required evidence;
`requiredEvidence` and `gates` may be empty for an observation. The manifest
accepts local static PNG/JPEG originals. For a candidate image:

```json
{
  "version": 1,
  "images": [{
    "path": "candidate.png", "purpose": "candidate", "source": "Authorized render of SC-01",
    "capture": {"record": "capture.json", "sha256": "CAPTURE_SHA256", "verifiedBy": "main agent"}
  }]
}
```

`capture.json` records the actual authorized collection:

```json
{
  "command": "ACTUAL_RENDER_COMMAND", "head": "HEAD", "tree": "FULL_TREE",
  "scenario": "SC-01", "viewport": [1280, 720],
  "output": {"path": "candidate.png", "sha256": "IMAGE_SHA256"},
  "invocation": {"path": "invocation.log", "sha256": "INVOCATION_SHA256"}
}
```

Retain the real invocation log from the existing renderer or screenshot tool.
It must support the literal command, collection HEAD/tree and image SHA256;
the main agent checks the actual run, scenario, viewport and output before
setting `verifiedBy`. The capture record and log are each bound by their byte
SHA256. Image, capture-record and invocation paths are relative to the manifest
directory, stay below it and contain no symlinks. See
[the planning contract](planning-contract.md) for accepted fields and limits.
The coordinator checks consistency and snapshots originals and provenance;
the main agent is responsible for authenticity. A self-reported tree or a log
assembled after the fact cannot replace actual collection evidence.

For a reference image, use `purpose: reference`, describe its source and omit
`capture`. Candidate images without matching collection evidence remain
unbound observations. A visual gate needs a `COMPLETE` visual execution at the
same HEAD/tree, at least one bound candidate image and no unbound candidate
images. Add `visualExecutionId: VISUAL_ID` to that gate's review evidence entry;
its artifact must reference the visual execution's actual `final.json` and
`final_hash`. The reviewer receives those original snapshots and visual report.

When the approved plan requires the executor to consume the same inputs, set
`routing.inputs.visual` to
`{"executionId":"VISUAL_ID","inputIds":["INPUT_ID"],"report":true}` using the
complete visual execution and its full set of opaque input IDs. Missing or
changed originals block launch. The [visual report schema](visual-report.schema.json)
defines observations, inference, comparisons, uncertainty, unchecked areas and
STOP reasons. Keep private images and paths out of public evidence.

### Independent review and reconciliation

The scout and reviewer roles have no write or network access. Run one independent
comprehensive review for the plan's required review coverage. Review output is evidence, not replacement for required deterministic
checks. For proof work, the reviewer checks property sufficiency and assumptions,
imports to the delivered implementation, current candidate/environment evidence,
and unproved behavior. A passing proof of a reference model does not prove the
original implementation. Initial review covers the whole candidate. A later review covers the
new delta and its gate-ledger transition, expanding to the whole candidate
when the mapping or resulting behavior is uncertain. One narrowly deterministic
main-agent repair of a failed implementation gate is allowed only within the
accepted Engineering contract; capture the resulting tree and rerun invalidated
checks and reviews. Other changes return to bounded revision or planning.

Record exactly one main-agent implementation outcome: `APPROVE`, `REVISE`,
`BLOCK`, or `INCONCLUSIVE`. Approval requires complete scope, gate, and review
evidence. A stale plan, STOP condition, altered requirement, missing authority,
or unsound approach blocks and returns to planning. Preserve an inconclusive
runtime record and its original report; report its reason, `validation_error`
when present, and artifact paths.

For `invalid_final_output`, the main agent may finish implementation review
without another model call when the exact candidate is unchanged and the raw
report supplies complete review evidence. For example, an otherwise approving
report may have duplicated plan-deferred CI in `BLOCKED` coverage. Verify that
the affected checks were explicitly deferred, all current gates passed, and no
finding or review blocker remains unresolved. Preserve the original error and
raw report. A recorded main-agent conclusion alone does not create approval;
submit the supported dispositions to the existing coordinator:

```console
codex-improve reconcile REVIEW_ID RECONCILIATION.json
```

For a latest review with one finding disproved by an actual artifact:

```json
{
  "version": 1, "conclusion": "APPROVE",
  "findings": [{
    "index": 0, "disposition": "rejected",
    "evidence": [{"path": "/private/evidence/finding-0.log", "sha256": "SUPPORT_SHA256"}],
    "conclusion": "The recorded result demonstrates that the reported failure does not occur."
  }],
  "evidence": [],
  "reason": "All findings are disposed with evidence and all required gates and coverage pass."
}
```

Dispose every original finding exactly once by its zero-based index, with
`resolved`, `rejected` or `unresolved`, a nonempty conclusion and real artifact
references. `APPROVE` requires support for every finding and permits none
unresolved. With no findings, use `findings: []` and place support in the
top-level `evidence` array. Every support artifact uses `path` and `sha256` as
above and remains available unchanged. Overall conclusions are `APPROVE`,
`REVISE` or `BLOCK`; `reason` is required.

Reconciliation applies only to the latest review's evidenced findings or
`INCONCLUSIVE/invalid_final_output`. It revalidates candidate, settings, gates,
artifacts and exact required coverage; missing or ambiguous evidence prevents
approval. Candidate changes require revision and a new review. Successful
reconciliation saves a separate authenticated approval while retaining the raw
failure. It needs no new permission under the existing implementation
authorization; another model call still follows the approval rule above.

Preserve the uncommitted candidate. Implementation approval does not imply
integration or external acceptance.

## Checkpoint, dependencies, and acceptance

After all required reviews approve the exact candidate, including any
evidence-based reconciliation above, and after any required commit approval,
the main agent may create one local checkpoint:

```console
codex-improve checkpoint EXECUTION_ID FULL_TREE --message 'type: summary'
```

The coordinator runs native Git hooks, checks the resulting tree, and advances
the Improve branch only from its expected parent. A hook failure or mutation
leaves the original branch tip and evidence available. The local commit is a
resumable checkpoint; it does not authorize merge, push, publication,
deployment, activation, or worktree removal. Integration is a separate explicit
action that names the reviewed commit OID and expected target HEAD. It needs
an execution-bound review after the checkpoint, with the current checkpoint
HEAD and an additional dossier field:

```json
{"target":{"worktree":"ABSOLUTE_TARGET_WORKTREE","head":"TARGET_HEAD","mergeTree":"FULL_TREE"}}
```

Verify the target HEAD and precompute its merge result with the authenticated
checkpoint. `mergeTree` must equal the reviewed candidate tree. Target drift
or a different merge tree requires independent preparation and review of a new
merge candidate. With matching authenticated approval and separate integration
authority:

```console
codex-improve checkpoint EXECUTION_ID --integrate-oid CHECKPOINT_OID --target WORKTREE --expected-target TARGET_HEAD
```

A dependent approved plan may start only from a protected exact checkpoint:

```console
codex-improve next EXECUTION_ID CHECKPOINT_OID PLAN --lane economy|standard|deep|writer
```

Record the current checkpoint ID and lineage whenever its persistent identity
changes. Carry gate and review evidence only when the relevant candidate diff
and environment are demonstrably unchanged. Complete all agent-observable
gates before deferring a physical, human, or external acceptance check. Prepare
the exact target, owner, procedure, expected evidence, recovery, and drift
conditions in an Operational handoff when such an operation exists. Ask for
approval before a commit, push, deployment, integration, or other reserved
action. A pending check remains pending; `DONE` requires integration and all
required acceptance.

When remote GitHub CI is the only remaining step, query it at most once, then
report the exact head, run link, and remaining acceptance. Do not poll or
schedule follow-up unless the user explicitly requested monitoring.

## Reconcile and close out

Reconcile from read-only worktree, private state, gate, review, and checkpoint
evidence. Routine status/index bookkeeping under approved semantics is allowed
in an authorized writable phase. Material changes to requirements, scope,
authority, dependencies, or approach return to formal Plan Mode and a reviewed
replacement plan. A failed deferred check against an unintegrated candidate may
return to in-scope revision; a new requirement is a planning block.

Keep the worktree while acceptance is pending. Before proposing cleanup,
validate repository and plan ownership, inspect tracked/staged/untracked changes,
confirm integration, and record `git worktree prune --dry-run --verbose` as
evidence only. After explicit approval, remove a clean, safely merged worktree
and branch. Stop on dirty, unmerged, ambiguous, or cross-repository state.

Publish issues only on explicit user request. Carry the evidence a reviewer
needs, including affected versions, reproduction, quantitative results,
ruled-out alternatives, compatibility boundaries, and validation; keep secret
values out of public material.

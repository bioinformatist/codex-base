# Connected implementation and acceptance

Use this workflow after the user authorizes a reviewed plan. Audit and formal
planning remain read-only. The runtime accepts `1.0.0-codex.20` plans and current
task records. Historical files remain untouched; start a new task from a reviewed
current plan without importing their state or approval.

## Start one connected task

Verify the complete plan, baseline, anchors, scope, environment, routing,
Engineering contract, gates and STOP conditions against the repository. Resolve
relevant drift before dispatch. A plan file cannot grant protected metadata
access or external effects; those need explicit authority.

Prefer a clean worktree returned by the host's managed-worktree tool, supplying
its exact path using `--worktree`. It must match the full base commit in the same
repository. Otherwise the client creates a detached Git worktree at that base.
Ignored contents are absent by default. An authorized `--copy-from SOURCE
--include PATH` copies only named ignored files or directories from a physical
worktree in the same repository.

```console
codex-improve session PLAN REPOSITORY --base FULL_COMMIT --lane deep
```

Lanes are economy, standard, deep and writer; an explicit lane must match the
plan. Repeat `--grant .agents` / `--grant .codex` only for authorized grants.
`.git` stays read-only to agents. The host or Nix closure supplies selected
Codex, Git and coreutils; the literal plan launcher supplies project tools.

Keep stdin/stdout connected: this process holds the official App Server and
one loaded implementation root. JSON lines on stdin control the task. Stdout
carries readiness, operation results, native events, questions and terminal
reports. Wait for each result before sending dependent commands. Preserve the
returned task/workspace/native IDs, actual model/effort/permissions and usage.

```json
{"op":"turn"}
{"op":"status"}
{"op":"answer","requestId":1,"answers":{"question_id":{"answers":["Selected answer"]}}}
```

`turn` sends the full approved plan and Ponytail method. Optional `prompt` adds
an authorized in-scope continuation or revision. Native tools own dispatch,
messages, waits and authorized nested delegation. One writer per path;
independent concurrent changes need separate native worktrees. Scout and visual
observe by responsibility within the shared implementation permissions.

Read roles and root budgets from `config/roles.json`; plans may configure task
budgets. Implementation and descendants share 300000 native units by default;
formal review has a separate 100000. Hard enforcement overrides a host false
setting. Units are native accounting, not context length, dollars or a strict
zero-overshoot guarantee. Missing models/efforts fail. Continue and revise on
the same loaded implementation root.

After every code/test step, run its named check, apply Ponytail to new hunks,
rerun affected checks after simplification and record `ponytail=lean` or
`ponytail=simplified`. Preserve accepted semantics and required tests. A conflict
with a settled requirement is a STOP. Research checkpoints contain Question,
Finding with certainty, Evidence and Next before changing questions. Report
actual checks, omissions and risks in the executor JSON. Pure verification,
read-only and documentation-only steps need no code simplification pass.

## Freeze and capture

```json
{"op":"capture"}
```

The controller pauses new implementation submissions, discovers all descendants
with pagination, interrupts active turns and observes native terminal states.
For each loaded family member it lists, terminates and re-lists background
terminals, then rechecks activity and family membership. Root completion or an
interrupt response alone cannot prove stopped writers. Unconfirmed termination
is a STOP and cannot produce an approvable candidate.

Capture includes staged, unstaged, deleted, mode and nonignored untracked changes
using a temporary index. Unmerged entries block capture. It checks exhaustive
writePaths and protected grants without changing the real index. Implementation
agents never compute candidate/approval identity or send acceptance commands.

Keep the implementation root loaded and idle through checks and review. When a
gate needs an exact-tree build, capture first, export that tree, then build and
test from the export with outputs outside the candidate. Record actual inputs,
environment, commands and results. Reuse evidence only with a complete unchanged
input/environment mapping. Uncertainty invalidates the affected check; a changed
candidate always needs new approval.

## Independent formal review

Supply all required check gates' current PASS evidence before review. Required
review gates receive exact coverage alongside `scope`. For required G1:

```json
{
  "version":1,"taskId":"TASK_ID","head":"HEAD","tree":"TREE",
  "evidence":[{
    "gate":"G1","status":"PASS",
    "artifact":{"path":"/private/evidence/g1.log","sha256":"ARTIFACT_SHA256"},
    "environment":"EXACT_PLAN_ENVIRONMENT","head":"HEAD","tree":"TREE",
    "planHash":"PLAN_HASH"
  }],
  "notes":"Inspect the complete candidate, requirements, reasons and evidence."
}
```

Use returned identities, byte hashes, absolute artifact paths and exact gate
environments. Include required check gates once each; unknown/duplicate gates
fail. PENDING cannot satisfy an implementation gate.

```json
{"op":"review","tree":"TREE","dossier":"/private/review.json"}
```

Review starts a fresh Sol high local read-only root with a separate native
budget; descendants inherit it. The reviewer receives the full plan, reasons,
exact candidate, Ponytail method, gate evidence and original private images.
Inspect connected callers and tests, not just the diff or claimed gaps; never
repair code. Native web search and local images remain available. Apps/plugins
and GUI tools are disabled. Optional `reviewTools` names existing MCP tools
independently verified as read-only. The client checks their actual inventory
and annotations. Missing tools, writable exposure or unverified permissions block
review; a local sandbox cannot establish external tool authority.

Images use `{"op":"images","manifest":"/private/images.json"}` after capture.
The manifest has `version:1` and `images` entries with `path`, `purpose`
(`reference` or `candidate`) and `source`. Paths stay below its directory without
symlinks. Originals are decoded and privately snapshotted. Candidate images need
`capture:{record,sha256,verifiedBy}`. The record has `command`, full `head`/`tree`,
`scenario`, `viewport:[width,height]`, `output:{path,sha256}` and
`invocation:{path,sha256}`. Retain the actual renderer log supporting that
command, candidate and image hash; the main agent verifies authenticity before
setting `verifiedBy`. Assembled-afterward logs cannot replace collection evidence.
Unbound or stale candidate images cannot satisfy review.

Only complete valid `APPROVE` with exact unique coverage grants approval.
`REVISE` returns fixes to the still-loaded implementation root:

```json
{"op":"turn","prompt":"Apply these reviewed in-scope findings: ..."}
```

Freeze, capture, rerun affected checks and review again. `BLOCK` preserves missing
evidence or uncertainty. Cancellation, timeout, budget exhaustion, native failure,
invalid output and unknown results cannot approve. Allow at most two revision
rounds and one bounded in-scope recovery as skill rules; further work needs user
direction. Native deadlines, interruption and budget limits govern execution.
The coordinator adds no root or per-role attempt timer.

Plan, candidate, settings, permissions, evidence bytes, images, review method or
target drift invalidates approval. One deterministic main-agent gate repair is
allowed within the approved Engineering contract; other fixes return to the
implementation root. Recapture and rerun affected checks and review after either.

## Commit and integrate with separate authority

After independent approval, an authorized local checkpoint uses:

```json
{"op":"commit","tree":"TREE","message":"feat: reviewed change"}
```

The client verifies current approval, runs native Git hooks, checks the resulting
tree/parent and advances HEAD. Hook failure or mutation preserves the original
tip. The new HEAD needs fresh review before integration. Add
`target:{worktree,head,mergeTree}` to that dossier, using the exact target HEAD
and precomputed merge tree, which must equal the candidate tree. With fresh
approval and explicit integration authority:

```json
{"op":"integrate","target":"/physical/target","head":"TARGET_HEAD"}
```

The target must remain clean and unchanged. Push, publication, deployment,
installation and downstream edits retain separate authorization boundaries.
A dependent task starts a new authorized session from its approved exact base.
Mark unintegrated work IMPLEMENTED; DONE needs integration and all acceptance.
Remote CI alone remaining: query once, report exact head/link and pending
acceptance, then return control unless monitoring was explicitly requested.

## Cancel, close and inspect

```json
{"op":"cancel","target":"implementation"}
{"op":"cancel","target":"review"}
{"op":"close"}
```

Cancellation uses native interruption and confirmed freeze. Unknown termination
stays unknown with artifacts preserved. `close` freezes both trees and closes
the connection, ending budget continuity. Connection or loaded-root loss is a
STOP: preserve workspace, last confirmed usage and evidence. A cold resume, fork
or replacement root cannot silently reset the budget; a new root needs explicit
authority.

`codex-improve inspect TASK_ID` reads authenticated task summaries without a model
call; a summary cannot prove a live loaded root or continue it.
`codex-improve remove TASK_ID` is only for authorized cleanup of a closed,
integrated, task-created physical worktree at its recorded HEAD. Dirty, ignored,
unknown-owned or symlinked contents block removal. Host-managed worktrees remain
owned by their host tool. Preserve failed workspaces and evidence.

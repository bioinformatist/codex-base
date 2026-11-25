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

Confirm the plan's hardest-acceptance walkthrough is viable with the installed
tool and actual operator permissions. For bootstrap upgrades, keep the selected
executable, coordinator and roles fixed for this task; candidate capabilities
are delivery targets, not tools for accepting or rescuing this run. Use source,
existing events, static scenarios and offline fixtures for paid-run claims as
specified in the planning contract. Leave unobserved runtime behavior `NOT RUN`
and collect observations during otherwise required normal work only.

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
Root registrations are saved before start and updated as soon as a reliable
response supplies thread and session IDs. If the response is lost, use
`inspect` to see the unknown attempt. Only a start response establishes an ID.

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

Finish generation before freeze and capture. Run a Git-dependent synchronization
check in the frozen workspace after capture and confirm the candidate is
unchanged before export. A package made before capture needs verified
unchanged-input binding or a rebuild from the export. A written freeze procedure
does not prove that real agents or terminals stopped; unknown termination
blocks capture and acceptance.

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
  "notes":"1. Verified facts and sources: G1 artifact.\n2. Questions for independent judgment: inspect connected callers against the complete plan.\n3. Candidate or input changes: initial candidate."
}
```

Use returned identities, byte hashes, absolute artifact paths and exact gate
environments. Include required check gates once each; unknown/duplicate gates
fail. PENDING cannot satisfy an implementation gate.

Organize `dossier.notes` as verified facts with sources, questions still needing
independent judgment, and candidate or input changes. The reviewer also receives
a mechanical summary of current validated gate/status/artifact paths and hashes,
the complete plan and code entry points. Before a new review, freeze the previous
review root. `previousReview` retains only that immediately preceding review's
identity, binding, native result, raw/parsed report and diagnostics. It is
handoff context, never approval. Code observations without an exact mapping to
current inputs remain questions for the new reviewer to check independently.
Use `inspect` for earlier review rounds in `reviewHistory` and the current
`review`.

```json
{"op":"review","tree":"TREE","dossier":"/private/review.json"}
```

Review starts a fresh Astra 6.2 high local read-only root with a separate native
budget; descendants inherit it. The reviewer receives the full plan, reasons,
exact candidate, Ponytail method, gate evidence and original private images.
Inspect connected callers and tests, not just the diff or claimed gaps; never
repair code. Native web search and local images remain available. Apps/plugins
and GUI tools are disabled. Optional `reviewTools` names existing MCP tools
independently verified as read-only. The client checks their actual inventory
and annotations. Missing tools, writable exposure or unverified permissions block
review; a local sandbox cannot establish external tool authority.

The same computed check sets constrain the submitted schema, prompt and Rust
validation: `coverage.check` and `findings.check` use `scope` plus
`requiredEvidence`; `deferred_acceptance.check` uses only gates explicitly
declared as deferred acceptance. With no such gates, the array must be empty.
Coverage has exactly one entry per required ID. Missing, duplicate, unknown and
overlapping coverage/deferred IDs produce diagnostics naming the offending IDs.
CI, integration or physical acceptance can be deferred only when the plan
explicitly declares it.

`review` accepts a normal `COMPLETE` implementation, or a native-confirmed
`failed`/`interrupted` turn whose outcome is `budget_exhausted`, `timed_out`,
`cancelled` or `failed`. Each route requires the live connection, same loaded
implementation root, frozen descendants and terminals, valid candidate and write
scope, and current PASS evidence for every required check. Unknown or running
turns, completed turns with invalid reports, and executor `STOPPED` reports do
not qualify. The implementation result remains recorded separately from the
new independent review. Changed candidates require recapture, current evidence
and new approval.

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
evidence or uncertainty. Cancelled, timed out, exhausted, failed, invalid or
unknown review runs cannot approve. Allow at most two revision
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
stays unknown with artifacts preserved. Use `close` when work on the connected
task is finished. A ready task or a captured task awaiting review can also close.
The client freezes every registered root and verifies descendant ownership and
that turns and terminals have stopped. Archive begins once the terminal records,
bindings, frozen thread IDs and `closed` state are durable.

Read the `close` result and use `inspect` to recover per-ID archive status and
the App Server shutdown result. Archive reconciliation uses both paginated
archive lists and one 30-second deadline. A failed or unconfirmed cleanup can
leave `archive.status` at `partial` or `unknown` on a closed task. The client gives
its App Server five seconds to exit after closing stdin, then terminates that
child if needed. Closing ends budget continuity. Connection or loaded-root loss
during implementation or review is a STOP. Preserve the workspace, last
confirmed usage and evidence. A new root needs explicit authority.

All finish paths save cached report material, including failed turns, active
cancellation and connection/root/model errors. `status`, `finished`, `stopped`
and `inspect` expose `rawReport` (up to 64 KiB), parsed `report`, `reportError`,
review `coverageError`, `nativeError`, thread/turn IDs and the review's source
candidate binding. Oversized raw text is truncated at a UTF-8 boundary and marked
invalid. Native terminal state (`nativeStatus`) is separate from report verdict
and approval. Without `turn/completed`, it is `unknown`; `lastNativeStatus` and
last observed usage remain available. `finalUsage: null` means no trusted final
measurement; only a normally completed turn with matching native turn usage can
provide one.

After confirmed cancellation the client saves cached material before setting
`cancelled`, and clears approval even if normal completion was observed during
the operation. Later finish processing still retains the report. Error exits
save diagnostics from cache without new RPCs or reconnection. Only normal review
completion with valid report/coverage and unchanged binding can grant approval.

`codex-improve inspect TASK_ID` reads authenticated task summaries without a model
call; a summary cannot prove a live loaded root or continue it.
`codex-improve remove TASK_ID` is only for authorized cleanup of a closed,
integrated, task-created physical worktree at its recorded HEAD. Dirty, ignored,
unknown-owned or symlinked contents block removal. Host-managed worktrees remain
owned by their host tool. Preserve failed workspaces and evidence.

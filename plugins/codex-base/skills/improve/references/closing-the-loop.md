# Closing The Loop

Audit and planning remain read-only. An executor works in a new persistent Git
worktree; the main agent verifies the result and returns an implementation
verdict, with only the single deterministic gate-repair permission defined
below. The worktree is preserved until the user decides what to do with it.

## Environment preflight and resume

For `.14` or `.15`, pass the artifact's environment JSON as the first option.
Add an explicit protected-path grant only after user approval:

```console
codex-improve-exec --environment-json '<exact-json>' [--allow-protected-path .agents] [--allow-protected-path .codex] [--spark|--deep] <artifact>
codex-improve-exec --environment-json '<exact-json>' [--allow-protected-path .agents] [--allow-protected-path .codex] [--spark|--deep] --revise WORKTREE EXPECTED_TREE DOSSIER
codex-improve-exec --environment-json '<exact-json>' [--allow-protected-path .agents] [--allow-protected-path .codex] [--spark|--deep] --recover WORKTREE EXPECTED_TREE DOSSIER
codex-improve-exec --environment-json '<exact-json>' [--allow-protected-path .agents] [--allow-protected-path .codex] [--spark|--deep] --next CHECKPOINT PLAN
codex-improve-exec --status [WORKTREE_OR_EXECUTION_ID]
```

The runner validates the JSON against the artifact before creating or reusing a
worktree. It runs the declared probes before Codex and prints these stable
fields with every model-capable execution:

```text
IMPROVE_EXEC_INVOKED=0|1
IMPROVE_CONTRACT=...
IMPROVE_PROTECTED_PATHS=[]|[".agents"]|[".codex"]|[".agents",".codex"]
IMPROVE_EXEC_ENVIRONMENT_HASH=...
IMPROVE_EXEC_PREFLIGHT_COUNT=...
IMPROVE_EXEC_PREFLIGHT_STATUS=legacy_unchecked|passed|failed|mutated
IMPROVE_EXEC_PREFLIGHT_LOG=...
IMPROVE_EXEC_RESUME_MANIFEST=...
```

For `.15`, every execution also prints
`IMPROVE_EXEC_CLOSEOUT_ELIGIBLE=0|1`. Initial and `--next` additionally print
`IMPROVE_PLAN_SHA256=...` for the exact private plan snapshot; earlier contracts
retain their existing fields.

The grant is never inferred from artifact prose. Only `.agents` and `.codex`
are accepted, `.git` is always forbidden, and no flag retains the existing
denial. A granted root must be absent or a physical directory when the runner
checks the exact worktree. Root symlinks (including dangling symlinks) and
non-directory nodes fail closed before preflight or Codex. The runner checks
before the launcher and probes and repeats the check after probes and candidate
verification, immediately before Codex. A failure at the second boundary uses
the nonresumable mutated-preflight classification. Symlinks nested below a
physical granted directory remain governed by the sandbox. `.13`
artifacts retain their existing execution and resume semantics and reject
the protected-path option. `.14` and `.15` share the protected-path behavior.
Revisions and recoveries must restate the approved set; resume
reconstructs it from the authenticated manifest and accepts no override.

The preflight log, wrapper, and optional resume manifest are private execution
artifacts. Content-free metrics contain only the invoked Boolean, environment
hash, probe count, status, effective contract, and normalized protected-path
enum; they never contain argv, output, host paths, names,
candidate identities, or manifest contents.

Before a contracted execution launches preflight, the runner verifies
current-user ownership and makes the per-user Improve root, worktree root, and
specific worktree mode 0700. Initial and `--next` create that worktree beneath
the configured XDG root; revision and recovery must already reuse a worktree
beneath the same root. This repairs state created by the `.11` runner before
its private umask took effect. A contracted follow-up outside that boundary is
rejected before its launcher runs. Legacy unchecked execution keeps its
existing path.

A failed probe with an unchanged candidate returns conclusive `STOPPED`,
`environment_preflight_failed`, and `IMPROVE_EXEC_INVOKED=0`. It consumes
neither the initial-run recovery allowance nor a revision round. Correct the
external environment, then invoke the exact one-time handoff:

```console
codex-improve-exec --resume WORKTREE EXPECTED_TREE ARTIFACT_DIR
```

Resume accepts no lane or environment override. It validates current-user
private state, exact file modes and ownership, artifact hashes, generated role
data, repository and registered-worktree identity, candidate identity, original
mode, profile, environment, limits, base, and predecessor. It creates a fresh
execution ID and artifact directory. Environment and prompt inputs are each
captured once; the runner hashes and consumes those same private byte snapshots.
If preflight fails again, the new manifest
records attempt 1 and its parent; do not resume it again. Return `BLOCKED`.

If preflight changes the candidate, return
`environment_preflight_mutated_candidate` without a manifest. Caller signals
and other transport failures are also nonresumable. Never retry automatically,
migrate legacy artifacts, or ask an executor to call candidate, checkpoint, or
resume.

Artifacts declaring `.13`, `.14`, or `.15` require a matching environment JSON.
Artifacts declaring `.12` are unsupported and must be re-reviewed and restamped
before execution. Artifacts declaring `.11`, or no Improve contract, retain
`legacy_unchecked` behavior when no environment JSON is supplied. They may opt
in by carrying a matching block and CLI value. Any other declared contract
version fails closed.

## Execute A Plan

### Preconditions

Before dispatch:

- Confirm the repository is a Git repository and the plan exists.
- Confirm every plan dependency is `DONE`. Allow only the planning contract's
  code-only exception: the dependent plan must inline a dependency contract
  that names an actual landing commit and an observable code prerequisite.
  Verify that the commit is an ancestor of the execution baseline and that the
  prerequisite is observable before dispatch; implementation state or an
  unnamed expectation is not sufficient.
- Run the plan's drift check against the current `HEAD`.
- Check that uncommitted source changes do not overlap the plan. Initial
  execution starts from the caller's committed `HEAD`; `--next` starts from its
  explicit predecessor checkpoint. Neither inherits uncommitted caller state;
  only the plan text is inlined.
- Verify that the Engineering-contract impact matrix covers every planned change
  trigger and its generated or packaged artifacts. Files outside modification
  scope remain in scope for read-only impact analysis.
- If a matrix row requires an unapproved CI, policy, classifier, release,
  compatibility, or other contract edit, return `BLOCKED` before dispatch.
- Reconcile a stale plan instead of asking the executor to improvise.

### Dispatch

Run one executor:

```console
codex-improve-exec --environment-json '<exact-json>' <plan-artifact-path>
```

One explicit invocation runs one plan. Serial dispatch is the default. A plan
may be scheduled concurrently with another unit only when its `Execution
isolation` section says `parallel-eligible`, source dependencies permit it, and
every mutable external resource has the required logical isolation and
lifecycle evidence. The helper does not schedule, enforce, or infer parallel
eligibility.

Capture the returned worktree's complete identity with
`codex-improve-exec --candidate "$IMPROVE_WORKTREE"`. Pass the full
`IMPROVE_CANDIDATE_TREE` explicitly to every review, revision, and recovery;
the dossier applies only to that exact tree. A post-run
`IMPROVE_CANDIDATE_AVAILABLE=0` preserves the execution classification and
diagnostics but returns nonzero and cannot proceed to review.

Use `--spark` only when the plan records the Spark lane and satisfies every
eligibility rule in the planning contract:

```console
codex-improve-exec --environment-json '<exact-json>' --spark <plan-artifact-path>
```

Use `--deep` only for a plan whose ambiguity or technical depth justifies the higher reasoning cost:

```console
codex-improve-exec --environment-json '<exact-json>' --deep <plan-artifact-path>
```

The advisor records the lane and routing evidence; the main agent explicitly
invokes it without a per-dispatch user prompt. `--spark` and `--deep` are
mutually exclusive. The helper never parses the plan to select a lane.

The helper creates a branch and worktree from the current `HEAD`, selects
`improve-executor`, `improve-executor-spark`, or `improve-executor-deep`, inlines
the entire plan, and pins the lane model, reasoning effort, verbosity, sandbox,
approval policy, unrestricted outbound network access with the network proxy
disabled, writable roots, rollout budget, memory, goals, and multi-agent setting
at CLI precedence. All three executor lanes receive that unrestricted outbound
access; reviewer and scout profiles remain read-only and offline. Project and
user MCP servers, Web Search, hooks, apps,
plugins, skills, project configuration, and repository instructions remain
available. The runner does not ignore user configuration or treat MCP or Web
use as a failure. It preserves the worktree and diagnostic artifacts even if
execution fails. It
prints the validated executor report once, followed by stable handoff fields:

```text
IMPROVE_MODE=initial
IMPROVE_WORKTREE=...
IMPROVE_BRANCH=...
IMPROVE_BASE=...
IMPROVE_PROFILE=...
IMPROVE_EXECUTION_ID=...
IMPROVE_EXEC_EXIT=...
IMPROVE_EXEC_RESULT=...
IMPROVE_EXEC_EXIT_REASON=...
IMPROVE_EXEC_ELAPSED_SECONDS=...
IMPROVE_EXEC_MAX_EVENT_GAP_SECONDS=...
IMPROVE_EXEC_QUIET_INTERVAL_OBSERVED=...
IMPROVE_EXEC_ACTIVE_TIMEOUT_SECONDS=...
IMPROVE_EXEC_ACTIVE_TOKEN_LIMIT=...
IMPROVE_EXEC_ROLLOUT_BUDGET_EXHAUSTED=...
IMPROVE_EXEC_EVENT_LOG_LIMIT_HIT=...
IMPROVE_EXEC_INVOKED=...
IMPROVE_EXEC_ENVIRONMENT_HASH=...
IMPROVE_EXEC_PREFLIGHT_COUNT=...
IMPROVE_EXEC_PREFLIGHT_STATUS=...
IMPROVE_EXEC_PREFLIGHT_LOG=...
IMPROVE_EXEC_RESUME_MANIFEST=...
IMPROVE_EXEC_ARTIFACT_DIR=...
IMPROVE_EXEC_PROMPT=...
IMPROVE_EXEC_EVENT_LOG=...
IMPROVE_EXEC_FINAL_OUTPUT=...
IMPROVE_EXEC_DIAGNOSTIC_LOG=...
IMPROVE_EXEC_METRICS=...
```

The executor must touch only in-scope files, run verification, honor STOP conditions, and leave changes uncommitted. It must not merge, push, modify the plan index, remove the worktree, or launch other agents. It does not calculate or reconstruct plan or candidate identity and does not invoke candidate, checkpoint, or resume operations. It does not load or reread Improve, its references, or Ponytail; required repository skills remain available when an implementation need actually triggers them. It avoids purposeless repeated broad reads of unchanged long files and duplicate skill copies. Targeted rereads are allowed after editing the exact region, after truncated output, or to answer one named unresolved question.

Executor worktrees live under `$XDG_STATE_HOME/codex-improve/worktrees`, falling
back to `~/.local/state`, so an interruption or reboot does not silently discard
uncommitted work that is awaiting review or a user decision. Runtime processes
remain disposable; the worktree is the persistent recovery surface.

Each invocation snapshots its complete prompt once and keeps the prompt, Codex
JSONL events, final message, stderr diagnostics, and GNU timeout's verbose
signal record private under
`$XDG_STATE_HOME/codex-improve/executions`, falling back to `~/.local/state`.
Raw Codex output is never streamed to the caller. While Codex runs, the helper
prints at most one content-free heartbeat per minute with the current lifecycle
phase, elapsed time, event count, and event bytes. It records an observation
after three minutes without a new event but does not interrupt quiet reasoning
solely for that reason.

For `.15`, each artifact directory also contains a mode-0600 `execution.json`
record. The runner atomically refreshes this validated versioned record across
`preparing`, `preflight`, `executing`, `classifying`, and `finished`; it records
lineage, current candidate availability, environment/preflight state,
content-free event and token observations, final classification, and the next
caller action. `codex-improve-exec --status` prints the newest record;
an exact execution identity selects that run, while a worktree path selects its
newest run. The query is read-only, ignores legacy artifacts with no record,
does not invoke Codex, and fails closed on matching-state ambiguity or invalid,
nonprivate, or symlinked registry entries. A live agent message that happens to
say `COMPLETE` is not a final result: only transport classification moves the
record to `finished`.

The same `.15` invocation creates a user-owned mode-0700 physical cache root
below the caller's `XDG_CACHE_HOME` (or its standard fallback). It exports a
shared `CARGO_HOME`, a shared `npm_config_cache`, and a per-execution
`XDG_CACHE_HOME` identically to preflight and Codex, and grants the sandbox
write access only to that physical cache root. The runner does not copy ambient
Cargo/npm credentials or configuration into it. Earlier contracts keep their
existing cache environment and receive no cache-root grant.

Each initial, `--next`, revision, and recovery invocation creates one fresh
opaque lowercase execution identity from runtime-only values. The helper
overwrites any ambient value and exports the exact identity as
`IMPROVE_EXECUTION_ID` to Codex and its descendants. The prompt and stable
output carry the same value as authoritative metadata. Reviewer runs do not
receive an execution identity.

The identity is an isolation input, not an automatic database, namespace,
bucket, schema, tenant, lifecycle, or cleanup policy. A project plan chooses
the narrowest supported logical coordinate and gives exact idempotent commands
for every client—including repo-local MCP, tests, CLI tools, and the
application—to provision and select the same scope. Bootstrap includes any
required schema, module import, fixture, or migration. A shared endpoint,
server, or container may remain shared when logical write targets are isolated;
the executor does not start, stop, restart, or tear down a shared daemon unless
the plan assigns it that lifecycle.

Fresh IDs make retries and follow-ups use fresh ephemeral resources by default.
When revision or recovery must reuse persistent state, its dossier or the
plan's Operational handoff names the existing logical resource and lifecycle
owner explicitly. `--next` receives a fresh ID and inherits source lineage only
from its checkpoint; stateful-resource lineage requires an explicit handoff in
the later plan. Resource names never enter content-free runner metrics.

The helper validates both the JSONL transport and the executor's final report.
A valid `COMPLETE` or model-level `STOPPED` is conclusive, uses exit reason
`completed`, and returns zero. Classification precedence is caller signal,
event-log overflow, absolute timeout, an exact top-level JSONL object whose
`type` is `error` and whose `message` is
`shared rollout token budget exhausted` when Codex exits nonzero, then a generic
nonzero Codex exit, followed by the existing transport and final-report
validation. Extra fields on that error object are harmless; nested or quoted
text is not a match. Every failure is `INCONCLUSIVE` and returns one.
`IMPROVE_EXEC_EXIT` always retains the raw Codex or GNU timeout status, while
`IMPROVE_EXEC_ROLLOUT_BUDGET_EXHAUSTED` is always `0` or `1`. A private timeout
signal record, rather than status 124 or 137 alone, identifies a real deadline.
The helper never retries or invokes another profile. Every outcome preserves
the worktree, prompt snapshot, event log, final output, diagnostic log, and
timeout record for recovery and investigation.

Executor model output is internally constrained by
`references/executor-report.schema.json` and preserved as private `final.json`.
The Runner independently requires the exact five fields, nonblank string-array
items, and at least one step. `COMPLETE` requires `stoppedBecause: null`;
`STOPPED` requires a trimmed, nonempty reason other than case-insensitive
`none`.
Only then does the Runner atomically render compatible `final.txt`, with one
physical `STATUS:`, `STEPS:`, `FILES CHANGED:`, and `NOTES:` line and a
`STOPPED BECAUSE:` line only for `STOPPED`; arrays use compact JSON so embedded
newlines remain escaped. `IMPROVE_EXEC_FINAL_OUTPUT`, result/reason fields,
candidate fields, return codes, metrics, and lifecycle behavior remain
unchanged, and no public structured-output field is added.

A Spark model or entitlement failure is the same nonzero Codex failure as any
other executor failure: the result is `INCONCLUSIVE`, every artifact is
preserved, and control returns to the main agent. The helper never retries with
Spark, standard, or deep and never consumes another lane as a fallback.

Standard initial execution has a provisional 20-minute absolute timeout and a
120,000-token rollout budget with 60,000/30,000/10,000 reminders. Spark initial
execution keeps the 20-minute timeout and 100,000-token budget with
50,000/25,000/10,000 reminders. Deep initial execution keeps the provisional
30-minute timeout and 160,000-token budget with 80,000/40,000/15,000 reminders.
Standard and Spark revisions and recovery slices reuse their profile token
budgets with a provisional 12-minute timeout; deep revisions and recovery
slices reuse the Deep budget with an 18-minute timeout. The provisional
transport fuses use a five-second hard-kill grace, a 32 MiB event-log limit,
and a 64 KiB final-output limit. All of these numeric values are
metrics-calibrated safeguards, not product or compatibility contracts.

Content-free execution metrics are appended to
`$XDG_STATE_HOME/codex-improve/execution-metrics.jsonl`, with the same state
fallback. They contain execution identity, mode, profile, outcome, reason,
elapsed time, prompt and event byte counts, observed token counts, whether
usage was observed, total tool-event count, command-execution, file-change,
MCP-tool-call, and Web-search counts, maximum event gap, quiet observation,
active limits, and Boolean fuse flags including `rollout_budget_exhausted`.
For the environment contract, they add only the executor-invoked Boolean,
environment hash, preflight count, and preflight status.
Tool counts are diagnostic observations, not automatic success or failure
criteria.
They never include prompt or final content,
repository or worktree paths, plan names, command output, or diffs.

Inspect the preserved diagnostics whenever any fuse triggers. After at least 10
executions, compare time and token distributions separately by mode. Consider
raising a limit when normal completions frequently exceed 80% of it. When
ordinary work remains far below the limits but an executor loops, prefer
tightening the prompt or timeout over raising the token ceiling. Change runner
constants, executor profiles, this documentation, and exact-value tests
together; do not tune limits automatically.

After at least 10 Spark initial executions, the main agent may prepare a manual
calibration review using the existing content-free metrics and observed
acceptance defects. Do not tune thresholds or broaden Spark routing without
explicit user approval.

### Reconcile An Eligible Inconclusive Execution

For `.15`, the runner emits `IMPROVE_EXEC_CLOSEOUT_ELIGIBLE=0` or `1` without
changing its transport classification. Eligibility is `1` only when the result
is still `INCONCLUSIVE`, the JSONL event log is valid, the candidate is
available, and the exit reason is `rollout_budget_exhausted`,
`absolute_timeout`, `empty_final_output`, `invalid_final_output`, or
`final_output_limit`. It never converts, masks, or overrides the original
`INCONCLUSIVE` result or exit reason.

Eligibility opens one independent main-agent reconciliation path; it does not
retry Codex and is not automatic approval. Verify the private `plan.md` bytes
against `IMPROVE_PLAN_SHA256` and the reviewed plan, verify the returned
candidate identity, inspect the complete initial candidate diff and preserved
transport artifacts, and classify every done criterion and Engineering-contract
row against the gate ledger. For each gate and reviewer ID, preserve evidence
only when its complete trigger mapping and relevant environment identity prove
the candidate delta irrelevant. Missing or uncertain mappings fail closed by
invalidating that ID, and `always-invalidated` IDs always run.

If the candidate needs no edits and every invalidated implementation gate
passes, continue to ordinary implementation review while retaining and
reporting the original `INCONCLUSIVE` execution result. An exact deterministic
gate fault may use the single main-agent repair permission below. Remaining
executor work, contradictory semantics, new scope, an Engineering-contract
change, a plan/hash/candidate mismatch, missing required evidence, or a failed
gate prevents closeout reconciliation. A missing field or value `0` is never
inferred as eligible; follow the recovery and explicit-approval rules below.

### Recover An Inconclusive Initial Execution

Automatic recovery is available only when an initial execution is
`INCONCLUSIVE` with exit reason `rollout_budget_exhausted` or
`absolute_timeout`. Every other initial failure halts with the exact private
artifact paths and requires explicit user approval before another model call or
a plan change. A model-level `STOPPED` is conclusive and does not trigger
recovery. Revision and review `INCONCLUSIVE` outcomes retain the same
explicit-approval policy; recovery never applies to them.

Before recovery, the main agent inspects the exact private plan snapshot and
hash, preserved diff, final output, JSONL events, diagnostics, timeout record,
and gate ledger. Reconcile each done criterion and Engineering-contract row as
completed, partially completed, or remaining, and verify that every existing
hunk still traces to the approved plan and settled semantic anchors. Preserve
gate evidence only through its declared triggers; invalidate an incomplete or
uncertain mapping and every `always-invalidated` gate.
New scope, a changed Engineering contract, or contradictory semantics rejects
recovery and returns to planning or user approval. An inconclusive initial run
that left no required edits still needs one verification-and-closeout slice;
never convert it directly to approval merely because the diff is empty.

The main agent may decompose the remaining work once into one to three
dependency-ordered recovery slice dossiers. Store them beside the original plan
in the repository's existing plan artifact directory, using
`<plan>-recovery-1-<slice-number>-<slug>.md` unless that repository defines a
more specific naming convention. They inherit that directory's tracked,
ignored, and publication policy; Improve must not change any of those policies.
Runtime prompts, events, final output, diagnostics, timeout records, and metrics
remain private XDG state and never enter a repository dossier.

Each recovery dossier is self-contained for exactly one slice and contains:

- original plan artifact path, immutable plan hash, original execution profile,
  checkpoint, branch, worktree, and current diff identity;
- slice number, dependency order, objective, and the completed and remaining
  original criteria relevant to that slice;
- only the applicable semantic anchors and Engineering-contract rows;
- only the permitted modification paths and required read-only evidence paths;
- exact implementation gates, verification commands, expected evidence, and
  preserved execution artifact paths needed to understand the remainder; and
- explicit slice STOP conditions, including new scope, Engineering-contract
  change, contradictory semantics, and an unrecognized checkpoint.

Choose Spark, standard, or deep independently for the actual remaining
execution unit.
The original plan lane is not a constraint, and a recorded recovery seam is
only a hint. Use Spark only when the slice independently satisfies every Spark
eligibility rule; never force it for telemetry. Invoke exactly the selected
lane:

```console
codex-improve-exec --environment-json '<exact-json>' --recover "$IMPROVE_WORKTREE" "$IMPROVE_CANDIDATE_TREE" <dossier-file>
codex-improve-exec --environment-json '<exact-json>' --spark --recover "$IMPROVE_WORKTREE" "$IMPROVE_CANDIDATE_TREE" <dossier-file>
codex-improve-exec --environment-json '<exact-json>' --deep --recover "$IMPROVE_WORKTREE" "$IMPROVE_CANDIDATE_TREE" <dossier-file>
```

The helper validates and reuses the same registered linked
`refs/heads/codex/improve-*` worktree as revision mode, snapshots the dossier
once, and runs one fresh ephemeral executor through the selected profile's
existing revision timeout and token budget. It does not parse the dossier,
infer a lane, retry, fall back, or invoke a second Codex process. The slice
executor preserves the existing diff and settled semantics, touches only the
dossier's paths, and runs every named check. Its `COMPLETE` report means only
that one slice is complete.

Recovery is sequential in the same persistent worktree. After each completed
slice, the main agent reads the exact old-to-new candidate delta and gate-ledger
transition, expands into earlier hunks wherever mapping or behavior is
uncertain, verifies that the candidate remains within the original plan and
current dossier, and runs the invalidated slice gates before dispatching the
next dependency. Any recovery slice `STOPPED` or
`INCONCLUSIVE`, scope or semantic drift, failed gate, or Engineering-contract
change halts the attempt with the exact worktree, dossier, and private execution
artifact paths. Never decompose or recover a recovery slice. After all slices,
capture the new candidate identity, append its ledger transition, run only the
invalidated and `always-invalidated` gates, and continue through the ordinary
implementation review below. Recovery count alone never triggers a full suite.

### Revise Before Integration

A failed review or acceptance against the still-current pre-integration
worktree may receive at most two narrow revision rounds. Prepare a
decision-complete delta dossier containing:

- original plan path and immutable hash, plus only the affected semantic
  anchors, plan constraints, and Engineering-contract rows;
- revision round, current checkpoint, branch, worktree, original Spark,
  standard, or deep execution lane/profile as provenance, selected revision
  lane, current routing evidence, and diff identity;
- exact failing review or acceptance evidence;
- classification as an in-scope defect, changed requirement, unrelated
  environment failure, or new scope or Engineering contract;
- the approved semantic amendment, when one exists;
- permitted paths, affected gates, and exact verification commands;
- the old and expected candidate identities, changed paths, and gate-ledger
  entries showing preserved evidence and evidence that must be rerun;
  and
- explicit STOP conditions.

Classify the bounded revision under the current routing rules independently of
the original execution lane. Preserve the original lane/profile as provenance,
record `Selected revision lane` and its current routing evidence, and explicitly
dispatch that selected lane through the same helper:

```console
codex-improve-exec --environment-json '<exact-json>' --revise "$IMPROVE_WORKTREE" "$IMPROVE_CANDIDATE_TREE" <dossier-file>
codex-improve-exec --environment-json '<exact-json>' --spark --revise "$IMPROVE_WORKTREE" "$IMPROVE_CANDIDATE_TREE" <dossier-file>
codex-improve-exec --environment-json '<exact-json>' --deep --revise "$IMPROVE_WORKTREE" "$IMPROVE_CANDIDATE_TREE" <dossier-file>
```

The helper validates that the path is the root of a registered linked Git
worktree on `refs/heads/codex/improve-*`, reuses it without creating or removing
a branch or worktree, snapshots and passes the complete dossier exactly once to
a fresh ephemeral executor, and uses the same private bounded transport as an
initial run. The executor preserves the existing diff, does not reload Improve
or Ponytail, performs no broad recon, edits only dossier-authorized paths, and
runs only named affected checks. New scope, an Engineering-contract edit,
contradictory semantics, an unrecognized checkpoint, missing original execution
provenance, or missing selected-lane routing evidence is a STOP. A selected
revision profile differing from the original profile is not a STOP.

A changed requirement or new scope or contract returns to planning rather than
revision. An unrelated environment failure preserves the current acceptance
state and records its evidence. After integration, even an in-scope defect
starts from the current integrated baseline through initial mode and a new
worktree; never revise the obsolete pre-integration worktree.

### Stepwise checkpoint sequencing

This is a compact stepwise checkpoint contract. Every executor mode (initial,
revision, and recovery) must apply the same embedded checkpoint rubric after
each code/test-changing step before moving to the next step:

1. run the step's named verification immediately;
2. inspect only that step's new candidate delta for `delete`, `stdlib`,
   `native`, `yagni`, and `shrink` opportunities;
3. apply only semantics-preserving simplifications that keep required checks and
   repository rules;
4. rerun the step check and any explicitly invalidated earlier check after
   each simplification; and
5. record `ponytail=lean` or `ponytail=simplified` on the step item and keep
   finding dispositions in notes.

If a finding contradicts a settled plan or dossier requirement, the executor must
return `STOPPED` with a concrete reason. This is an in-process check; it does
not invoke another model, another prompt, or a Ponytail skill.

Documentation-only steps, pure reads, and pure verification are exempt. Missing
step-checkpoint evidence prevents `APPROVE` through ordinary `REVISE` or `BLOCK`;
it does not make the transport report structurally invalid or change report-schema
validation.

### Review

Treat the executor report and diff as untrusted until verified:

1. Map every done criterion to current gate-ledger evidence. Run each invalidated
   or `always-invalidated` implementation gate inside `IMPROVE_WORKTREE`; do not
   rerun a full suite solely because the candidate has a revision or recovery.
2. Compare `git -C <worktree> status --short` and `git -C <worktree> diff --stat` with the plan's scope.
3. For the initial implementation review, read the complete diff and verify each
   hunk traces to a plan step. After a recovery, revision, or permitted repair,
   read the exact candidate delta and gate-ledger transition, expanding to the
   complete diff wherever the mapping or resulting behavior is uncertain.
4. Inspect new tests for meaningful assertions, not only passing commands.
5. Reconcile the actual diff, generated artifacts, dependency graph, public
   interfaces, and runtime effects with the Engineering-contract impact matrix.
   An unexplained trigger or out-of-scope impact returns to planning; a required
   unapproved contract edit `BLOCK`s. Omission is not evidence that the impact
   is absent.
6. Run applicable repository checks in evidence-preserving order. Capture a
   clean base/head delta before builds, caches, installations, deployments, or
   other local state can hide it, or use an isolated equivalent.
7. Perform the main-agent implementation pass. Check behavior, tests, repository
   rules, reuse, justified abstraction, module boundaries, locality, speculative
   flexibility, compatibility layers, and removable code.
8. Apply the installed `$ponytail-review` skill once to the current diff. Record
   both its raw suggestions and the main agent's disposition in the bounded
   dossier. Treat suggestions as hypotheses; reject any that weaken settled
   semantics, correctness, repository rules, or necessary tests. Its line-count
   score is not an acceptance criterion. No independent reviewer repeats this
   skill pass for the same diff.
9. Decide whether external-practice evidence or an independent review is
   required under the triggers below.

#### Single deterministic gate repair

Audit, planning, and plan review remain read-only. During execution review, the
main agent may perform at most one direct candidate repair when a deterministic
implementation gate identifies one exact in-scope fault and the correction is
mechanical under the already approved semantics and Engineering contract.
Before editing, record the failing command and assertion, old candidate tree,
permitted paths, and ledger IDs the edit invalidates. After editing, capture the
new tree, record the exact delta, run every invalidated or `always-invalidated`
gate, and review that delta through the ledger rules above.

This permission never applies to reviewer feedback, changed requirements, new
scope, public behavior, dependencies, schemas, architecture, an uncertain root
cause, or any Engineering-contract change. Those cases STOP direct repair and
return to ordinary revision or planning. The repair is not an ordinary revision
round: it neither consumes nor increases the two-round revision allowance. It
is single-use across the candidate lifecycle, cannot recurse, and cannot repair
its own failed or newly exposed gate; that outcome is `REVISE` or `BLOCK` under
the ordinary policy.

#### External-practice evidence

Use external-practice evidence when a structural decision materially depends on
an external ecosystem convention. New dependencies and compatibility layers
normally qualify. Public APIs, protocols, formats, OS integration, modules, and
abstractions qualify only when external guidance could distinguish plausible
designs. Purely internal organization with a settled repository precedent does
not qualify.

The main agent first verifies the normative or upstream position with the
applicable documentation skill, current official documentation, standards,
ADRs, RFCs, migration guides, release notes, upstream examples, or verified
maintainer explanations. Record exact versions, links, the upstream rationale,
and any unresolved applicability question. Do not delegate authoritative-source
selection or maintainer-identity verification to the practice scout.

Launch one read-only practice scout only when first-hand community evidence
could still materially qualify the upstream position or distinguish the
candidate approaches. Give `improve-scout` one exact decision question,
relevant versions, repository constraints, candidate approaches, the verified
upstream position and links, and the evidence that would support, qualify, or
contradict it. It may inspect the repository and public sources but must not
edit, launch agents, re-research a supplied authoritative conclusion without a
specific conflict, or issue a verdict:

```console
timeout 8m <path-to-skill>/scripts/codex-improve-scout \
  "$IMPROVE_WORKTREE" <practice-memo> \
  > <practice-events> 2> <practice-diagnostics>
```

The caller owns that eight-minute timeout. The bundled helper does not retry or
fall back, and plugin-only callers resolve it from the loaded Improve skill
root. Nix users may use the `codex-improve-scout` PATH shorthand.

The scout treats generic articles as leads only and searches first-hand
maintainer discussions, issue reports, postmortems, benchmarks with disclosed
harnesses, and production reports. It fills a fixed evidence matrix:

- community evidence supporting the supplied upstream position;
- counterexamples or reported failure modes;
- material version, platform, scale, security, or compatibility differences;
- applicability to the repository constraints; and
- missing, disputed, or unavailable evidence.

Each cell ends as `SUPPORTED`, `CONTRADICTED`, `NOT_FOUND`, or
`NOT_APPLICABLE`. Search only unresolved cells, never repeat an equivalent query
without new evidence, and treat `NOT_FOUND` as a valid result after a targeted
pass over the appropriate first-hand sources. Emit one compact progress message,
preserved in the JSONL event log, after ingesting the supplied upstream position
and naming unresolved cells, and another after the community pass before final
synthesis. When every cell has a state, render the memo immediately. Stop with
explicit uncertainty when sources remain incompatible; never manufacture a
universal best practice.

The local Markdown memo contains the decision question, versions and
constraints, supplied upstream position and links, the completed evidence
matrix, repository applicability, uncertainties, candidate implication, and
source links. The main agent verifies each material community claim before
using it, gives the already verified upstream guidance the greatest weight, and
retains the final judgment. Upstream guidance does not override a version,
platform, security, or repository constraint without analysis.

Run at most one scout for a materially unchanged decision, never retry
automatically, and do not apply the reviewer rollout-token budget to this role.
The eight-minute timeout is a separate, provisional practice-scout fuse based on
an observed non-convergent run; it is not an established best practice or a
reviewer threshold. Preserve the JSONL checkpoints and diagnostics. A timeout,
missing memo, or otherwise incomplete run is `INCONCLUSIVE` and requires
explicit approval before another attempt or a plan change. Any application that
would change settled scope or an Engineering contract must `BLOCK` for
approval.

#### Independent review triggers

Run the correctness reviewer when behavior is consequential or ambiguous. Run
the elegance reviewer for a new abstraction, module, public interface,
dependency, compatibility layer, cross-owner boundary, complex lifecycle,
concurrency or security logic, a material disagreement about structure, or an
explicit repository or user requirement. A narrow revision reruns a reviewer
only when it invalidates that reviewer's evidence.

#### Bounded evidence dossier

For each triggered independent review, the main agent prepares one complete
dossier for a reviewer with no conversation context. It is not a transcript and
does not ask the reviewer to rediscover the repository. Include:

- the exact current plan artifact, its immutable baseline commit, settled
  semantic anchors, and Engineering contract;
- the Engineering-contract impact matrix reconciled against the actual diff,
  including generated artifacts and every out-of-scope impact;
- for an initial review, the baseline and complete diff boundary plus a
  changed-path manifest; for a later review, the old and new candidate trees,
  exact delta, and gate-ledger transition, expanded to the complete boundary
  wherever uncertainty remains;
- executor and main-agent verification results, including generated-artifact
  evidence when applicable;
- implementation gates, deferred acceptance checks, and observations as three
  separate lists; independent reviewers cover implementation gates only;
- the single Ponytail pass and the main agent's disposition of each suggestion
  when that lens applies;
- the verified practice memo when external evidence applies;
- the exact checks and questions assigned to this reviewer; and
- the applicable host-injected repository instructions, clearly distinguished
  from ordinary repository evidence.

Do not include secret values. The dossier must remain sufficient for a fresh
reviewer after interruption or compaction. Missing material evidence produces a
`BLOCK` verdict; it never authorizes a broad repository audit.

The reviewer builds a coverage matrix for every requested implementation check
before new recon. Deferred acceptance is reported separately and cannot create
a finding, failed coverage row, or review blocker merely because it has not run.
The reviewer does not reload the Improve skill, planning contract, audit
playbook, or Ponytail skill. It reads each changed artifact completely at most
once. Any reread names one unresolved question first and targets only the range
needed to answer it.
When rollout-budget reminders report 50,000 weighted tokens remaining, broad
recon stops and the coverage matrix is completed. At 25,000, only one named
evidence gap may be pursued at a time. At 10,000, tool use stops and the verdict
is rendered.

#### Review runner

Invoke only the applicable roles through the same bounded transport:

```console
codex-improve-review elegance "$IMPROVE_WORKTREE" "$IMPROVE_CANDIDATE_TREE" <dossier-file>
codex-improve-review correctness "$IMPROVE_WORKTREE" "$IMPROVE_CANDIDATE_TREE" <dossier-file>
```

The helper selects `improve-elegance-reviewer` or `improve-reviewer`, passes the
dossier once, and runs `codex exec --strict-config --ephemeral --json
--output-schema`. It preserves the JSONL event log, structured final output, and
diagnostic log under `$XDG_STATE_HOME/codex-improve/reviews`, falling back to
`~/.local/state`, so an interrupted review remains diagnosable. An eight-minute
absolute fuse is the last-resort runtime boundary. Three minutes without a new
JSONL event is recorded as a quiet-interval observation but never treated as
proof of a stalled model or used to interrupt the run. Bounded evidence and
model-visible rollout budgets remain the primary convergence controls.

Both reviewer profiles use a 100,000 weighted-token limit with
50,000/25,000/10,000 convergence gates. Those values, together with the
1.0 sampling and prefill weights, eight-minute fuse, three-minute observation
marker, and two-revision boundary are provisional reviewer-only calibrations.
Observe elapsed time, token mix, tool events, maximum JSONL event gap, verdict,
and failure reason in subsequent reviews. Do not tune them automatically. A
change requires evidence from observed runs and explicit user approval.

The helper reports the role, profile, result, artifact paths, elapsed time,
maximum event gap, quiet-interval observation, exit reason,
`IMPROVE_REVIEW_ACTIVE_TOKEN_LIMIT=100000`, and the stable `0` or `1`
`IMPROVE_REVIEW_ROLLOUT_BUDGET_EXHAUSTED` field. Its model output
must satisfy [`review-verdict.schema.json`](review-verdict.schema.json) and keep
the verdict coherent with its findings, implementation coverage, review
blockers, and deferred acceptance. `APPROVE` may include deferred acceptance,
but never a finding, failed coverage row, or review blocker. A model verdict is
possible only when Codex exits successfully with valid JSONL and a
coherent structured result; otherwise the result is `INCONCLUSIVE`. After
wrapper signals and absolute timeout, an exact top-level JSONL error object with
the shared rollout-budget exhaustion message and a nonzero Codex status is
classified as `rollout_budget_exhausted`; extra fields are allowed, while
nested or quoted text does not match. A generic nonzero exit follows that
classification, before existing validation and verdict behavior. Invalid
caller input or unavailable local storage may terminate before a complete
handoff. Metrics are content-free and best-effort, include numeric
`active_token_limit` and Boolean
`fuse_flags.rollout_budget_exhausted`, and contain no paths or review content.
The helper never retries or falls back to another role or profile.

The correctness reviewer checks behavior, safety, regressions, meaningful
tests, and plan and Engineering-contract compliance. The elegance reviewer
checks reuse, justified abstraction, module boundaries, locality, speculative
flexibility, unnecessary compatibility layers, and removable code. It considers
the main agent's already recorded Ponytail pass without rerunning or reloading
that skill. Ponytail suggestions remain hypotheses: reject any that weaken
settled semantics, correctness, repository rules, or necessary tests, and never
use its line-count score as an acceptance criterion. Elegance review does not
expand product scope or reopen settled user decisions without new contradictory
evidence.

The main agent validates every reviewer finding against the dossier and diff,
then follows the single implementation-review policy below. It never overrides
a triggered review's `INCONCLUSIVE` status or tunes a provisional boundary on
its own.

After an approved main-agent implementation review, the advisor records all
three facets in the plan and any index before deriving lifecycle:

- **Implementation review**: `APPROVED`.
- **Checkpoint**: `NONE`, `RESUMABLE`, or `INTEGRATED`, with an exact
  checkpoint ID whenever it is not `NONE`.
- **External acceptance**: `NOT REQUIRED`, `PENDING`, `PASSED`, or `FAILED`.

Derive `IMPLEMENTED` while implementation is approved but no deferred
acceptance is ready against a resumable or integrated checkpoint. Derive
`ACCEPTANCE PENDING` only when a named deferred acceptance is ready against that
exact checkpoint. Derive `DONE` only when the atomic change is integrated and
external acceptance is `PASSED` or `NOT REQUIRED`.

Implementation approval establishes neither integration nor acceptance.

Render exactly one main-agent implementation outcome. A triggered reviewer returns
a model verdict as evidence; `INCONCLUSIVE` remains a separate helper status:

- `APPROVE`: criteria pass, scope is clean, and implementation quality holds. Report the diff summary, branch, worktree path, and material notes. Do not commit, merge, or push.
- `REVISE`: prepare the complete revision dossier and invoke the helper's matching normal or deep `--revise` form against the same preserved pre-integration worktree. Rerun only invalidated checks and reviewers, and stop after two revision rounds.
- `BLOCK`: the plan is stale, a STOP condition occurred, required or not-yet-approved scope expanded, including an Engineering-contract change, or the approach is unsound. Return to planning and ask for user approval before changing direction.
- `INCONCLUSIVE`: report the helper's exact exit reason and preserved diagnostic
  paths, halt integration, and ask for explicit approval before another review
  attempt or a plan change. Never convert it to `APPROVE`.

### Deferred acceptance handoff

After `APPROVE`, complete every agent-observable implementation gate before
deferring work to a person or external system. For each deferred acceptance:

1. Prepare the exact target. Use the persistent worktree plus base and diff
   identity for a local synchronous check, or a commit, branch, PR, preview,
   deployment, or other repository-backed identity for an asynchronous or
   cross-machine check.
2. Ask for approval before any commit, push, deployment, integration, or other
   action that repository rules or the user reserve for approval.
3. Record the checkpoint ID and append a lineage row whenever its persistent
   identity changes. Carry review evidence forward only after proving the
   reviewed diff is unchanged; otherwise mark the applicable evidence invalid.
   For stateful work, add the conditional Operational handoff with target and
   checkpoint, owner, host or environment, working directory, complete commands
   or physical procedure, prerequisites, temporary runtime mutations, cleanup
   state and evidence, expected evidence, recovery, drift invalidation, and
   secret locations or credential types without values.
4. Stop executor, reviewer, server, and other processes that are not themselves
   part of the named acceptance environment. Return control with the plan and
   checkpoint sufficient to resume in a later turn.
5. Record the result. `PASSED` may advance an integrated change to `DONE`.
   Before integration, `FAILED` returns to `IN PROGRESS` for an in-scope defect
   and may use bounded revision. Against an integrated checkpoint, the same
   plan may record the failure, but execution starts in initial mode from the
   current integrated baseline and a new worktree. A changed requirement,
   scope, authority, or approach returns to `BLOCKED` planning. An unrelated
   environment outage remains `ACCEPTANCE PENDING` with evidence.

Human feedback across turns is a normal pause in the Improve loop, not a
terminated execution. Resume from the plan and checkpoint rather than from
conversation recollection.

### Closeout

Closeout is a separate, explicit action and operates only on the worktree named
by the current plan. Retain it while acceptance is pending. Before proposing
cleanup:

1. confirm the worktree belongs to the current repository and plan;
2. inspect tracked, staged, and untracked changes;
3. inspect whether its branch is safely integrated; and
4. record `git worktree prune --dry-run --verbose` as evidence only.

After explicit user approval, use `git worktree remove <worktree>` and
`git branch -d <branch>` only for a clean, safely merged result. Forced removal
requires separate explicit discard approval. STOP on dirty, unmerged,
ambiguous, or cross-repository state; never infer that the user no longer wants
the worktree.

## Reconcile

For each indexed plan:

- `TODO`: compare modification and evidence/drift paths with the stamped commit;
  refresh evidence, commands, and scope when drifted.
- `IN PROGRESS`: verify that an executor or revision is actually active. Resume
  review when active. Otherwise inspect the preserved worktree and record the
  lifecycle state its evidence supports; do not leave a stale `IN PROGRESS`.
- `IMPLEMENTED`: verify the scoped diff and executor checks, locate the actual
  landing commit if integrated, and derive the next state from the three facets.
  A known deferred check without a ready resumable target remains `IMPLEMENTED`.
- `ACCEPTANCE PENDING`: verify implementation review is `APPROVED`, the named
  deferred check is ready, and the checkpoint ID still identifies the exact
  target. Verify its result without treating implementation approval or landing
  alone as acceptance. Advance to `DONE` only after integration and every check.
- `DONE`: verify the integrated implementation, checks, and acceptance evidence,
  then record or confirm the actual landing commit.
- `BLOCKED`: verify whether the blocker still exists; revise the plan only when
  the original approach remains valid.
- `REJECTED`: preserve the rationale and verify only whether new evidence makes
  deliberate re-planning appropriate; do not silently reactivate it.

Obsolete or independently fixed work becomes `REJECTED` with a one-line
rationale rather than being deleted. Reconciliation follows the planning
contract's authority, semantic-anchor, and material-change rules for every
state transition. It may report closeout candidates and dry-run prune evidence,
but never removes a worktree or branch implicitly and never scans another user
or unrelated repository's Improve state.

## Publish Issues

Only publish when `--issues` was explicitly requested. Before creating issues, check repository visibility. For a public repository, obtain explicit confirmation before publishing security findings, credential locations, private architecture, or operational details. Record each issue URL in the plan and index.

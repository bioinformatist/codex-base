# Closing The Loop

Audit and formal planning remain read-only. After the user authorizes a reviewed
plan, the main agent saves it and delegates implementation through the public
`codex-improve` coordinator. Read the planning contract for plan, environment,
role, gate-ledger, and lifecycle requirements. The current source runtime accepts
only `1.0.0-codex.17`; older private execution state is retained separately and
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
codex-improve execute PLAN REPOSITORY --lane economy|standard|deep
codex-improve status [EXECUTION_ID]
codex-improve candidate WORKTREE
```

The coordinator reads the one `.17` environment block in the plan, creates an
isolated Worktrunk worktree from a committed base, snapshots the plan and role,
runs the literal launcher and bounded probes, then launches official `codex exec`
with the selected role. The caller may specify a full committed `--base OID`.
Worktrunk's automation hooks and LLM commits are disabled; the later reviewed
Git checkpoint runs native Git hooks. The caller supplies host Codex, Worktrunk,
Git, and Python 3.11 or newer for a portable install; Nix packages the runtime
closure. The coordinator does not download dependencies or infer a project
launcher. Python runs with `-B` against installed plugin resources.

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
Then inspect only its new candidate delta for `delete`, `stdlib`, `native`,
`yagni`, and `shrink` opportunities. Apply only semantics-preserving
simplifications, rerun the step check and any invalidated earlier check, and
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
to gaps claimed by an executor handoff. Use separate read-only dossiers and
the full expected tree:

```console
codex-improve review correctness WORKTREE FULL_TREE DOSSIER.md
codex-improve review elegance WORKTREE FULL_TREE DOSSIER.md
codex-improve scout WORKTREE FULL_TREE DOSSIER.md
```

The scout and review roles have no write or network access. Trigger independent
correctness or elegance review when the plan's risk and review contract require
it. Review output is evidence, not replacement for required deterministic
checks. Initial review covers the whole candidate. A later review covers the
new delta and its gate-ledger transition, expanding to the whole candidate
when the mapping or resulting behavior is uncertain. One narrowly deterministic
main-agent repair of a failed implementation gate is allowed only within the
accepted Engineering contract; capture the resulting tree and rerun invalidated
checks and reviews. Other changes return to bounded revision or planning.

Record exactly one main-agent implementation outcome: `APPROVE`, `REVISE`,
`BLOCK`, or `INCONCLUSIVE`. Approval requires complete scope, gate, and review
evidence. A stale plan, STOP condition, altered requirement, missing authority,
or unsound approach blocks and returns to planning. An inconclusive review
stays inconclusive; report its reason and artifact paths. Preserve the
uncommitted candidate for review. Do not treat implementation approval as
integration or external acceptance.

## Checkpoint, dependencies, and acceptance

After all required reviews approve the exact candidate, and after any required
commit approval, the main agent may create one local checkpoint:

```console
codex-improve checkpoint WORKTREE FULL_TREE --message 'type: summary'
```

The coordinator runs native Git hooks, checks the resulting tree, and advances
the Improve branch only from its expected parent. A hook failure or mutation
leaves the original branch tip and evidence available. The local commit is a
resumable checkpoint; it does not authorize merge, push, publication,
deployment, activation, or worktree removal. Integration is a separate explicit
action that names the reviewed commit OID and expected target HEAD:

```console
codex-improve checkpoint --integrate-oid REVIEWED_OID --target REPOSITORY --expected-target TARGET_HEAD
```

A dependent approved plan may start only from a protected exact checkpoint:

```console
codex-improve next EXECUTION_ID CHECKPOINT_OID PLAN --lane economy|standard|deep
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

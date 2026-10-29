# Handoff Plan Template

Write for an executor with zero conversation context. Inline every
decision-bearing constraint, give each step an exact verification and expected
result, and state scope and STOP conditions. The planning contract owns the
semantics; this file supplies their filled-in shape.

Follow the repository's artifact convention. Otherwise use local-only
`plans/NNN-short-slug.md`, or `advisor-plans/NNN-short-slug.md` when `plans/`
already has another purpose, numbered in recommended execution order.

## Template

````markdown
# Plan NNN: <Imperative title — what will be true>

> **Executor instructions**: Reread this complete plan before editing. Recover
> its objective, anchors, scope, Engineering contract, checks, and STOP
> conditions; then execute the ordered steps. Run each verification and confirm
> its expected result before continuing. Leave the plan and index unchanged.
>
> After every code/test-changing step, run its named verification; inspect only
> that step's new delta for `delete`, `stdlib`, `native`, `yagni`, and `shrink`
> opportunities; apply only semantics-preserving simplifications; rerun the step
> check and explicitly invalidated earlier checks; record `ponytail=lean` or
> `ponytail=simplified` on the step and put finding dispositions in notes. STOP
> if a finding conflicts with a settled requirement.
>
> **Drift check (run first)**: `<exact command comparing Planned-at SHA through
> HEAD across every Modification scope and Evidence/drift path>` → no relevant
> drift, or the live state matches the Current state after explicit comparison.
> A mismatch is a STOP. The runner owns the plan snapshot/hash and candidate
> identity; never calculate, reconstruct, or update either, or invoke candidate,
> checkpoint, or resume operations.

## Status

- **Status**: TODO
- **Improve contract**: `1.0.0-codex.19`
- **Implementation review**: PENDING | APPROVED | REVISE | BLOCKED
- **Checkpoint**: NONE | RESUMABLE | INTEGRATED
- **External acceptance**: NOT REQUIRED | PENDING | PASSED | FAILED
- **Checkpoint ID**: none
- **Priority**: P1 | P2 | P3
- **Effort**: S | M | L
- **Risk**: LOW | MED | HIGH
- **Executor lane**: economy | standard | deep | writer
- **Executor routing evidence**: <why this lane satisfies the routing contract>
- **Recovery seams**: none | <one to three dependency-ordered seams with paths, gates, and candidate lane>
- **Depends on**: none | <plan identifier; inline any code-only exception's exact approved checkpoint or landing commit and observable prerequisite>
- **Category**: bug | security | perf | tests | tech-debt | migration | dx | docs | direction
- **Artifact policy**: <repository convention, or local-only fallback>
- **Planned at**: commit `<short SHA>`, <YYYY-MM-DD>
- **Issue**: <URL only when explicitly published; otherwise omit>

## Objective

<What changes, why it matters, and the bounded outcome.>

## Acceptance surface

<The one concrete API, CLI, preview, or real consumer that makes this unit
independently observable, integrable, reversible, and acceptable.>

## Route checkpoint

<Omit for a standalone plan. When triggered, fill every field.>

- **Program outcome**: <chain-level user outcome>
- **Present bottleneck**: <current decision or constraint>
- **Fresh evidence**: <named result or observation selecting this route>
- **Route claim**: <why this is still a necessary next unit>
- **Cheapest discriminator**: <least expensive confirming/redirecting/stopping check>
- **Inherited artifacts**: <artifact plus product-bound, research-only, or retire-before-integration disposition>

<Only for a route-selecting evidence plan: add this exhaustive result map;
at least one row must settle the route.>

| Result | Meaning | Continue, redirect, or stop |
|---|---|---|
| <material result> | <meaning> | <action> |

## Semantic anchors

<List concise, stable anchors using only populated provenance prefixes: `U`
user decision, `F` verified fact, `D` derivation, `A` assumption, `R` rejected
alternative. Preserve IDs across revisions.>

## Review record

- **Reviewed baseline**: <identity>
- **Evidence refreshed**: <paths/results>
- **Material semantic changes**: none | <change and provenance>
- **Verdict**: READY | BLOCKED — <reason/input needed>

## Checkpoint lineage

<The scalar Checkpoint and Checkpoint ID above are authoritative. Omit this
section until identity changes; then append one row per transition.>

| Stage | Identity | Superseded identity | Preserved evidence | Invalidated evidence |
|---|---|---|---|---|

## Execution environment

<Replace placeholders with the exact reviewed literal argv values. Probes may
be empty; the environment block accepts no omission-reason field.>

```json codex-improve-environment
{
  "version": 1,
  "launcher": ["env"],
  "probes": [],
  "cache": {"xdgScope": "execution"}
}
```

<Omitting `cache` means fresh per-execution XDG scope. Add
`"cache":{"xdgScope":"worktree"}` only with evidence that expensive state
must survive revision/recovery in this registered worktree; record the rationale
in Semantic anchors and add a clean-state gate. Cache hits are never evidence.
The coordinator reads this block directly from the plan. Do not include secrets
or environment-variable values.>

## Execution isolation

- **Dispatch**: serial | parallel-eligible
- **Mutable stateful resources**: none | <table below>

| Resource | Isolation coordinate | Provision/select | Lifecycle owner | Cleanup |
|---|---|---|---|---|
| <service> | <logical scope> | <idempotent commands> | <owner> | <policy/evidence> |

## Current state

- **Relevant files and roles**: <exact paths, symbols, and short current excerpts with line markers>
- **Applicable conventions**: <rule plus exact exemplar path>
- **Vocabulary/design constraints**: <inline decision-bearing lines; point to stable background by exact path and section>
- **Current evidence**: <facts/results the executor must not rediscover>

## Engineering contract

<One row per planned trigger. Modification scope limits writes, not impact
analysis. Mark N/A only with repository evidence. `pending approval` makes the
plan BLOCKED; after approval add its paths and checks to this plan.>

| Concern | Planned change trigger | Requirement or command | Repository evidence | Expected result | Contract edit |
|---|---|---|---|---|---|
| Build/generated artifacts | <trigger/N/A> | <command/N/A> | <path/rule> | <result> | <no/pending approval/approved> |
| Test/lint/type | <trigger/N/A> | <command/N/A> | <path/rule> | <result> | <...> |
| CI/policy/classifier | <trigger/N/A> | <gate/N/A> | <path/rule> | <result> | <...> |
| Compatibility/public interface | <trigger/N/A> | <check/N/A> | <path/rule> | <preserved behavior> | <...> |
| Release/deployment | <trigger/N/A> | <check/N/A> | <path/rule> | <result> | <...> |
| Review/acceptance | <trigger/N/A> | <review/N/A> | <path/rule> | <result> | <...> |

## Verification and acceptance contract

### Stronger verification (conditional)

<Omit this section for ordinary verification. When selected during planning,
fill every field; existing project proof contracts remain binding even when
this section is omitted.>

- **Selection and properties**: <reason, exact properties, preconditions, domain boundaries; why properties exclude materially wrong results>
- **Implementation correspondence**: <delivered paths/symbols, proof imports and transitive implementation links; reference-model distinction and uncovered behavior>
- **Property ownership and scope**: <target-project laws/proofs/tests, allowed edits and protected property paths; agreed property changes require explicit plan revision>
- **Procedure and limits**: <tool versions/provenance, cwd and literal commands, success/failure diagnostics and exit criteria, task budget; STOP/report unfinished work without gate downgrade>
- **Evidence binding**: <existing gate IDs below, candidate and environment identity, invalidation triggers including imported code/properties; no separate evidence schema>

### Routing and gates

```json codex-improve-routing
{"version":1,"lane":"standard","writePaths":["src/**"],"requiredEvidence":["G1"]}
```

<Choose exact repository-relative files or glob patterns. For writer, add the
settled materials described in planning-contract.md; for required visual
inputs, name their authenticated execution and opaque input IDs there.>

```json codex-improve-gates
{
  "version": 1,
  "gates": [{
    "id": "G1",
    "class": "implementation gate",
    "kind": "check",
    "check": "<exact command and expected result>",
    "invalidatedBy": ["<paths or always-invalidated>"],
    "environment": "<toolchain/probes and environment identity>",
    "conditions": "<required environment conditions>"
  }]
}
```

<One gate block is the check ledger. Classify each gate once as implementation
gate, deferred acceptance, or observation. Check gates require structured
artifact evidence; review gates are produced by independent review. All
implementation gates belong in requiredEvidence. Unknown invalidation mappings
invalidate evidence. Append candidate transitions and evidence references in
execution/review dossiers, without repeating the gate definitions here.>

## Operational handoff

<Omit unless stateful or deferred work exists. Otherwise record target and
checkpoint; owner; host/environment and working directory; prerequisites;
complete commands or physical procedure; temporary mutations; cleanup state and
evidence; expected evidence; recovery; drift invalidation; and secret locations
or credential types without values. For each deferred acceptance, include its
exact environment, procedure, result, rollback/recovery, and invalidating drift.
An asynchronous handoff requires a resumable Checkpoint and exact ID.>

## Scope

**Modification scope** (exhaustive writable paths):

- `<path>` — <planned edit>

**Evidence/drift paths** (read-only inputs):

- `<path>` — <fact, convention, or drift checked>

**Out of scope** (explicit exclusions):

- `<path or behavior>` — <why excluded>

## Git workflow

- Branch/worktree: created by `codex-improve execute`; create no replacement.
- Leave executor changes uncommitted for main-agent review.
- The executor must not edit plan/index artifacts, invoke candidate/checkpoint/resume
  operations, commit, merge, push, publish, deploy, integrate, or remove the worktree.
- The main agent owns plan/index updates and any separately authorized lifecycle
  actions. It may create a local checkpoint through the runner only after all
  required reviews approve; that checkpoint does not authorize integration,
  publication, deployment, or cleanup.

## Steps

### Step 1: <Imperative title>

<Exact files/symbols, target behavior/code shape, and bounded action.>

**Verify**: `<exact command>` → <expected result>

**Step evidence**: <`ponytail=lean` or `ponytail=simplified`; dispositions when required>

### Step 2: <Imperative title>

<Continue in dependency order; each step is independently checkable.>

**Verify**: `<exact command>` → <expected result>

**Step evidence**: <`ponytail=lean` or `ponytail=simplified`; dispositions when required>

## Test plan

- **New/changed tests**: <exact file and happy path, regression, and named edge cases>
- **Structural exemplar**: <exact existing test path/symbol>
- **Commands**: `<exact command>` → <all tests pass, including count/cases when stable>

## Done criteria

- [ ] <Every implementation gate has current passing evidence.>
- [ ] <Acceptance surface exhibits the required behavior.>
- [ ] <Required tests exist and pass.>
- [ ] <Only Modification scope paths changed; generated companions are accounted for.>
- [ ] <Plan/index artifacts remain unchanged by the executor.>

## STOP conditions

- Current state or drift evidence contradicts the plan.
- A named verification still fails after one reasonable in-scope correction.
- Work requires an unapproved Engineering-contract change or path outside Modification scope.
- <Plan-specific assumption, dependency, authority, or safety boundary fails.>

## Maintenance notes

- <Future interaction or intentionally deferred follow-up and why.>
- <What implementation reviewers must scrutinize.>
````

## Optional index

The advisor may maintain this concise index at the repository-specific artifact
location after review:

```markdown
# Implementation Plans

Execute in dependency order. Each executor reads its complete plan; the advisor
updates lifecycle after review.

| Plan | Title | Priority | Effort | Depends on | Status |
|---|---|---|---|---|---|
| 001 | ... | P1 | S | — | TODO |

Status: TODO | IN PROGRESS | IMPLEMENTED | ACCEPTANCE PENDING | DONE | BLOCKED
(reason) | REJECTED (rationale). `ACCEPTANCE PENDING` requires approved
implementation, a ready deferred check, and a RESUMABLE or INTEGRATED checkpoint
with exact ID.

Dependency notes and findings deliberately rejected: <concise entries as needed>.
```

## Final coverage check

Confirm the plan is zero-context executable; every decision, new mechanism, and
boundary has provenance; every step and gate has an exact expected result; scope
and drift lists match the drift command; STOP conditions name actual risks; the
Planned-at SHA is filled; conditional sections are present exactly when
triggered; and no secret value appears.

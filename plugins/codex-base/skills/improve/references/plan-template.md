# Handoff Plan Template

Every plan is written for an executor model that has **zero context**: it has not seen the advisor session, the audit, the other plans, or any prior conversation. It may be a smaller/cheaper model. Assume it is competent at following explicit instructions and weak at filling gaps, recovering from ambiguity, or knowing when to stop.

Three properties make a plan executable by a weaker model:

1. **Decision-complete context** — inline every decision-bearing constraint; point to stable background by exact repository path and section.
2. **Verification gates** — every step ends with a command and its expected result. The executor never has to *judge* whether it succeeded.
3. **Hard boundaries and escape hatches** — explicit out-of-scope list, and "STOP and report" conditions instead of letting the model improvise when reality doesn't match the plan.

File naming: follow the repository's explicit artifact convention. Otherwise use local-only `plans/NNN-short-slug.md`, or `advisor-plans/NNN-short-slug.md` when `plans/` already has another purpose, numbered in recommended execution order.

---

## Template

```markdown
# Plan NNN: <Imperative title — what will be true after this plan>

> **Executor instructions**: Before editing, reread this complete plan and recover its objective, Semantic anchors, Modification scope, evidence/drift paths, Engineering contract, checks, and STOP conditions. Then follow it step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. Leave the plan and index unchanged; the advisor
> updates lifecycle state after review.
> After every code/test-changing step, run its named verification, inspect only
> that step's delta for `delete`, `stdlib`, `native`, `yagni`, and `shrink`
> opportunities, and rerun invalidated checks after each accepted simplification.
>
> **Drift check (run first)**: `git diff --stat <planned-at SHA>..HEAD -- <Modification scope and evidence/drift paths>`
> If any path in Modification scope or evidence/drift paths changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.
> The runner owns the exact plan snapshot/hash and candidate identity. Do not
> calculate, reconstruct, or update either identity, and do not invoke candidate,
> checkpoint, or resume operations.

## Status

- **Status**: TODO
- **Improve contract**: `1.0.0-codex.15`
- **Implementation review**: PENDING
- **Checkpoint**: NONE
- **External acceptance**: NOT REQUIRED | PENDING
- **Checkpoint ID**: none
- **Priority**: P1 | P2 | P3
- **Effort**: S | M | L
- **Risk**: LOW | MED | HIGH
- **Executor lane**: spark | standard | deep
- **Executor routing evidence**: <why this lane satisfies the Improve routing contract>
- **Recovery seams**: none | <one to three dependency-ordered seams, each with relevant paths, gates, and a candidate lane>
- **Depends on**: <plan artifact identifier at the repository-specific location> (or "none"); inline every dependency contract so execution never requires conversation context or another plan
- **Category**: bug | security | perf | tests | tech-debt | migration | dx | docs | direction
- **Planned at**: commit `<short SHA>`, <YYYY-MM-DD>
- **Issue**: <issue URL — only when published via `--issues`; omit otherwise>

## Semantic anchors

Persist concise material semantics with stable provenance prefixes: `U` user decision, `F` verified fact, `D` advisor derivation, `A` assumption, and `R` rejected alternative. Include only populated categories and preserve identifiers across review.

## Review record

Record the reviewed baseline, refreshed evidence, material semantic changes with provenance, and the `READY` or `BLOCKED` verdict.

## Checkpoint lineage

Keep the scalar Checkpoint and Checkpoint ID above authoritative. Omit lineage rows until that persistent identity changes. Then append:

| Stage | Identity | Superseded identity | Preserved evidence | Invalidated evidence |
|-------|----------|---------------------|--------------------|----------------------|

## Execution environment

Declare the exact launcher and literal preflight probes for this execution.
Use an empty launcher to inherit the runner environment. Empty probes require
`probeOmissionReason`.

```json codex-improve-environment
{
  "version": 1,
  "launcher": [],
  "probes": [],
  "probeOmissionReason": "<why no project-specific probe is required>"
}
```

The main agent passes this exact reviewed JSON first through
`--environment-json`. Do not include secrets or environment-variable values.
For a `.15` initial or `--next` invocation, the runner snapshots these exact
plan bytes privately and returns their SHA-256. Record that returned identity
in later dossier or ledger provenance; do not edit the executed plan to embed
its own hash.

## Execution isolation

- **Dispatch**: serial
- **Mutable stateful resources**: none

When mutable external state is required, replace `none` with:

| Resource | Isolation coordinate | Provision/select | Lifecycle owner | Cleanup |
|----------|----------------------|------------------|-----------------|---------|
| `<service>` | `<scope derived from execution ID or explicit handoff>` | `<exact commands>` | `<owner>` | `<policy/evidence>` |

## Why this matters

2–5 sentences. The problem, its concrete cost, and what improves when this
lands. Written so the executor (and a human reviewer) understands the intent —
intent is what lets a correct judgment call happen when a detail is off.

## Acceptance surface

Name the one concrete surface that makes this unit independently observable,
integrable, reversible, and acceptable: a testable API or CLI, runnable
preview, or real consumer. Keep only its minimum supporting foundation here.
Split independent outcomes, rollback boundaries, or unresolved decisions; do
not use line, file, directory, or layer quotas.

## Current state

The facts the executor needs, inlined — never "as discussed" or "see audit":

- The relevant files, each with one line on its role:
  - `src/orders/api.ts` — order-list endpoint; contains the N+1 (lines 130–160)
- Excerpts of the code as it exists today (short, with `file:line` markers),
  enough that the executor can confirm it's looking at the right thing.
- The repo conventions that apply here, with a pointer to one exemplar file:
  "Error handling follows the Result pattern — see `src/lib/result.ts` and its
  use in `src/users/api.ts:40-60`. Match it."
- Any documented vocabulary or design constraints the plan must honor, inlined
  from the intent/design docs found in recon: the relevant `CONTEXT.md` terms
  the executor should use in names and comments, the `DESIGN.md` tokens/components
  to reuse, or the ADR whose decision this work must stay consistent with. Quote
  the specific decision-bearing lines. Stable non-decision background may be
  referenced by exact repository path and section.

## Engineering contract

Record one row for every planned change trigger. Modification scope limits edits, not read-only impact analysis; record a concern as not applicable only with repository evidence.

| Concern | Planned change trigger | Requirement or command | Repository evidence | Expected result | Contract edit |
|---------|------------------------|------------------------|---------------------|-----------------|---------------|
| Build/generated artifacts | `<package, generated output, or N/A>` | `<exact command or N/A>` | `<path, config, or documented rule>` | `<observable result>` | `<no, pending approval, or approved>` |
| Test/lint/type | `<behavior or source change>` | `<exact command or N/A>` | `<path, config, or documented rule>` | `<observable result>` | `<no, pending approval, or approved>` |
| CI/policy/classifier | `<artifact, dependency, or workflow impact>` | `<exact gate or N/A>` | `<path, config, or documented rule>` | `<observable result>` | `<no, pending approval, or approved>` |
| Compatibility/public interface | `<interface, format, or dependency change>` | `<boundary check or N/A>` | `<path, config, or documented rule>` | `<preserved behavior>` | `<no, pending approval, or approved>` |
| Release/deployment | `<packaging, runtime, or rollout impact>` | `<exact check or N/A>` | `<path, config, or documented rule>` | `<observable result>` | `<no, pending approval, or approved>` |
| Review/acceptance | `<risk or user-visible impact>` | `<required review or N/A>` | `<path, config, or documented rule>` | `<observable result>` | `<no, pending approval, or approved>` |

Run state-sensitive checks before a build, cache, installation, deployment, or other local state can hide their evidence, or use clean base/head isolation. Any `pending approval` contract edit requires an evidence-backed `BLOCKED` verdict; after approval, mark it `approved`, add the exact edit paths to Modification scope, and add the exact checks to this table and the verification commands. Adding ordinary behavior tests inside an existing harness does not require approval.

## Verification and acceptance contract

Classify every check exactly once. Implementation gates are deterministic or agent-observable and must pass before implementation approval. Deferred acceptance is limited to behavior the available agent and environment cannot exercise. Observations are non-blocking unless an explicit threshold and lifecycle transition are recorded.

| Check | Class | Owner | Stage and target | Required evidence |
|-------|-------|-------|------------------|-------------------|
| `<exact check>` | `<implementation gate, deferred acceptance, or observation>` | `<executor, main agent, user, or external system>` | `<before review, checkpoint ID, or after integration>` | `<command output or observable result>` |

### Gate ledger

Use stable IDs. Triggers name paths, interfaces, generated outputs, environment
inputs, or other facts that invalidate evidence. Declare a genuinely holistic
gate `always-invalidated`; revision or recovery count is never a trigger.

| Gate ID | Command/reviewer | Invalidation triggers | Environment identity | Current candidate evidence |
|---------|------------------|-----------------------|----------------------|----------------------------|
| `G1` | `<exact command or reviewer ID>` | `<paths or always-invalidated>` | `<toolchain/probe/checkpoint identity>` | `<candidate tree, result, artifact>` |

After every candidate transition the main agent appends one row. Preserve an ID
only when its complete trigger mapping and relevant environment identity prove
the delta irrelevant. Missing or uncertain mapping fails closed by invalidating
that ID. Run invalidated and `always-invalidated` IDs; revision or recovery
count alone never requires the full suite.

| Old candidate | New candidate | Changed paths | Preserved gate/reviewer IDs | Invalidated IDs and reasons |
|---------------|---------------|---------------|-----------------------------|-----------------------------|

Initial implementation review covers the complete candidate diff. Later review
covers the candidate delta plus this ledger transition and expands to the
complete diff wherever the mapping or resulting behavior is uncertain.

When the Checkpoint ID changes between worktree/diff, commit, PR, integration, preview, or deployment, append one Checkpoint lineage row with the stage, new identity, superseded identity, preserved evidence, and invalidated evidence. Preserve evidence only after proving the reviewed diff is unchanged; a material diff change invalidates its applicable checks and reviewer conclusions.

For stateful or deferred operations, add an Operational handoff with the target and checkpoint, owner, host or environment, working directory, complete commands or physical procedure, prerequisites, temporary runtime mutations, cleanup state and evidence, expected evidence, recovery, and drift invalidation. Name secret locations or credential types only, never values. Omit Operational handoff when no stateful or deferred operation exists.

For every deferred acceptance, record the environment, exact procedure, expected evidence, rollback or recovery path, and what drift invalidates the result. Before an asynchronous handoff, the main agent records a resumable Checkpoint and exact Checkpoint ID; the executor never creates or integrates that checkpoint on its own.

## Commands you will need

| Purpose   | Command                  | Expected on success |
|-----------|--------------------------|---------------------|
| Install   | `pnpm install`           | exit 0              |
| Typecheck | `pnpm typecheck`         | exit 0, no errors   |
| Tests     | `pnpm test -- <filter>`  | all pass            |
| Lint      | `pnpm lint`              | exit 0              |

(Exact commands from this repo — verified during recon, not guessed.)

## Suggested executor toolkit

(Optional — include only when relevant skills/tools plausibly exist in the
executor's environment. Skip the section otherwise.)

- Skills the executor should invoke if available, and for what:
  "use `vercel-react-best-practices` when writing the memoization in step 3".
- Reference docs worth reading before starting, by path or URL.

## Scope

**Modification scope** (the only files you should modify):
- `src/orders/api.ts`
- `src/orders/api.test.ts` (create)

**Evidence/drift paths** (read-only inputs used to verify facts and baseline drift):
- `src/lib/result.ts`

**Out of scope** (do NOT touch, even though they look related):
- `src/orders/legacy-api.ts` — deprecated path, scheduled for deletion;
  changing it wastes effort and risks the v1 clients still pinned to it.
- Any change to the public response shape — clients depend on it.

## Git workflow

(Filled from recon — match the repo's observed conventions.)

- Branch and worktree: created by `codex-improve-exec`; do not create another branch
- Leave all executor changes uncommitted for the main agent to review
- Do not commit, merge, push, open a PR, or remove the worktree.

## Steps

### Step 1: <imperative title>

What to do, precisely. Reference exact files/symbols. Include the target code
shape when it's load-bearing (the pattern to produce, not necessarily every
line).

**Verify**: `<command>` → <expected output>

### Step 2: ...

(Each step small enough to verify independently. Order steps so the codebase
is never broken between steps when possible — e.g. add new path, switch
callers, then remove old path.)

## Test plan

- New tests to write, in which file, covering which cases (list them:
  happy path, the specific bug/regression this plan fixes, named edge cases).
- Which existing test to use as the structural pattern:
  "model after `src/users/api.test.ts`".
- Verification: `<test command>` → all pass, including N new tests.

## Done criteria

Machine-checkable. ALL must hold:

- [ ] `pnpm typecheck` exits 0
- [ ] `pnpm test` exits 0; new tests for <X> exist and pass
- [ ] `grep -rn "<old pattern>" src/` returns no matches
- [ ] No files outside Modification scope are modified (`git status`)
- [ ] Plan artifacts and any repository-specific plan index remain unchanged by the executor

## STOP conditions

Stop and report back (do not improvise) if:

- The code at the locations in "Current state" doesn't match the excerpts
  (the codebase has drifted since this plan was written).
- A step's verification fails twice after a reasonable fix attempt.
- The fix appears to require touching an out-of-scope file.
- You discover the assumption "<key assumption>" is false.

## Maintenance notes

For the human/agent who owns this code after the change lands:

- What future changes will interact with this (e.g. "if pagination is added
  to this endpoint, the batching in step 2 must be revisited").
- What a reviewer should scrutinize in the PR.
- Any follow-up explicitly deferred out of this plan (and why).
```

---

## Optional index at the repository-specific artifact location

Written and maintained by the advisor after review:

```markdown
# Implementation Plans

Generated by the improve skill on <date>. Execute in the order below unless
dependencies say otherwise. Each executor reads the plan fully before starting and
honors its STOP conditions; the advisor updates status after review.

## Execution order & status

| Plan | Title | Priority | Effort | Depends on | Status |
|------|-------|----------|--------|------------|--------|
| 001  | ...   | P1       | S      | —          | TODO   |
| 002  | ...   | P1       | M      | 001        | TODO   |

Status values: TODO | IN PROGRESS | IMPLEMENTED | ACCEPTANCE PENDING | DONE | BLOCKED (with one-line reason) | REJECTED (with one-line rationale — finding fixed independently or approach abandoned). Derive ACCEPTANCE PENDING only when implementation review is APPROVED, a deferred acceptance is ready, and Checkpoint is RESUMABLE or INTEGRATED with an exact Checkpoint ID.

## Dependency notes

- 002 requires 001 because <reason>.

## Findings considered and rejected

- <finding>: not worth doing because <one line>. (So nobody re-audits it.)
```

## Quality bar — check before finishing each plan

- Could a model that has never seen this repo execute this with only the plan file and the repo? If any step requires knowledge from the advisor session, inline that knowledge.
- For every new limit, cap, dependency, abstraction, compatibility layer, or defensive mechanism, is provenance explicit from a user decision, observed repository fact/failure, repository rule, or authoritative external constraint?
- Is every verification a command with an expected result, not a judgment ("make sure it works")?
- Could each new mechanism be replaced by existing repository rules, standard shell, or built-in tooling without weakening requirements?
- Does every step name exact files and symbols, not "the relevant module"?
- Are the STOP conditions specific to this plan's actual risks, not boilerplate?
- Would a reviewer reading only "Why this matters" + "Done criteria" understand what they're approving?
- No secret values anywhere in the file — locations and credential types only.
- "Planned at" SHA is filled in and the Modification scope plus evidence/drift paths in the drift check match the Scope section.

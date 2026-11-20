# Improve lifecycle ownership and new tasks

Improve `.20` / runtime `0.20.0` reads only current plans and task records in
`codex-improve-v20`. Historical files stay where they are, without import,
continuation, migration or inherited approval. Finish active tasks with their
original runtime before updating. To begin new work, review a current `.20` plan
and authorize a new task at an explicit base; history is evidence, not authority.

## Responsibility changes

| Previous responsibility | Current owner / entry | Deleted implementation or dependency | Remaining gap and removal condition |
|---|---|---|---|
| Per-call role runner, dispatch, messages and waiting | Official connected App Server and native team tools | `lifecycle.rs`, `transport.rs`, role-runner and their exclusive tests | `session.rs` translates the approved plan and results; remove when native workflow can enforce the same plan/acceptance contract |
| Per-role token quotas and attempt timers | Native root rollout budget; implementation 300k, review 100k | Role tokenLimit/reminders, initial/follow-up timeout matrix, process/quiet/heartbeat supervision | Explicit enforcement/config and outcome adaptation remain; no custom meter, quota proxy or root timer |
| Worktree inventory and lifecycle | Host managed-worktree tool, or detached Git worktree at exact base | Worktrunk package/skill and duplicate inventory | Git common-dir/base/physical ownership, explicit ignored includes and safe cleanup remain until equivalent native checks cover them |
| Candidate, evidence and approval identity | Git temporary index and deterministic Rust acceptance kernel | Old record formats and lifecycle approval plumbing | `contracts.rs`, `reviews.rs`, `git_worktree.rs` bind plan, actual settings, full tree, artifact bytes and target/merge tree; native completion alone does not replace this |
| Freeze and independent acceptance | Native descendant/turn/terminal APIs; fresh read-only Astra 6.2 high root | Per-role isolated execution services and visual runner | Paged freeze and read-only MCP allowlist checks stay until native atomic freeze/acceptance supplies equivalent proof |
| Complete logs and agent lifecycle | Codex native history | Parallel transport/event logs and session database | Private authenticated task summaries retain necessary native IDs, candidate, usage and review evidence only |
| Automatic dependency updates and public-X adapter | Manual maintenance and ordinary research | Dedicated updater/workflow, Renovate and ADHX source/distribution | External bot and installed marketplace state require separate authorized action; see [updating](updating.md#retired-automation-and-installations) |

## Starting and controlling a task

The user continues to invoke `$improve` (plugin: `$codex-base:improve`) in Codex.
The advisor saves a reviewed plan only in an authorized writable phase, then
uses the connected client below. Users need not manually orchestrate JSON.

```console
codex-improve session PLAN REPOSITORY --base FULL_COMMIT --lane deep
```

Prefer `--worktree` with a host-managed tool's returned clean path at that base.
Otherwise Git creates a detached task-owned worktree. Default copies exclude
ignored content; an authorized `--copy-from SOURCE --include PATH` names exact
ignored inclusions. `.agents`/`.codex` need explicit grants, and agents retain
`.git` read-only. Same-path changes have one writer; isolate independent parallel
changes. Scout/visual observe within shared task authority; formal review is a
separate local read-only root whose descendants inherit it.

Keep stdin/stdout connected throughout implementation, continuation, review and
revision. Commands are JSON lines: `turn` starts/continues implementation,
`capture` freezes writers then returns HEAD/tree, `images` imports private
originals/provenance, and `review` supplies the exact tree and evidence dossier.
`status` reads current facts; `answer` relays a native structured question.
Review coverage is exactly `scope` plus the plan's `requiredEvidence` IDs. The
submitted schema, prompt and Rust validation use the same IDs; diagnostics name
missing, duplicate, unknown or overlapping checks. Only acceptance explicitly
declared deferred by the plan may remain pending. Complete valid APPROVE with
unchanged binding grants approval; other review results cannot. REVISE returns
to the original loaded implementation root.

`review` also accepts a confirmed native failed/interrupted implementation with
outcome budget_exhausted, timed_out, cancelled or failed. It still requires the
same connected loaded root, confirmed freeze of all writers and terminals,
valid candidate/scope and current PASS evidence. Unknown/running turns, invalid
completed reports and executor STOPPED do not qualify. The implementation's
terminal result remains separate from independent acceptance.

`dossier.notes` carries verified facts with sources, questions for independent
judgment, and candidate/input changes. The prompt includes a validated
gate/status/artifact/hash summary and only the immediately preceding
`previousReview` diagnostic snapshot. A new review first freezes the old review
root and independently rechecks observations that cannot be mapped to current
inputs. The snapshot carries no approval.

Commit, integration and cleanup are separate authorized operations. `close`
freezes both roots and ends the connection. `inspect TASK_ID` reads an
authenticated summary after closing; it cannot reconnect or prove continuity.
Connection/loaded-root loss stops the task with last confirmed usage and
artifacts retained. A cold resume/fork or new root requires explicit new-budget
authority. There is no runtime fallback to historical contracts.

Normal, failed and cancelled turns retain bounded raw text, parsed JSON, report
and coverage diagnostics, native errors and thread/turn IDs; review records also
retain their source candidate binding. Cancellation saves the report after
confirmed freeze and grants no approval, including a completion race. Error
exits save cached diagnostics without RPCs. `nativeStatus` is `unknown` until
`turn/completed`; `lastNativeStatus` and last usage remain available.
`finalUsage: null` explicitly means the final measurement is unknown. These facts
are visible through `status`, terminal events and authenticated `inspect`.

See the canonical [connected workflow](../src/improve/references/closing-the-loop.md)
for command shapes, review dossier and image collection evidence. Gate results
may be reused only when their actual input/environment mapping is unchanged;
new candidates always require new approval. Unintegrated work is IMPLEMENTED;
DONE requires integration and all acceptance.

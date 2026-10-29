# Improve lifecycle ownership

The Improve runtime accepts plan contract `1.0.0-codex.19`. Earlier execution
artifacts stay in their original namespaces and are never migrated or resumed
by this version. Current state uses `codex-improve-v19`. The following map
records lifecycle ownership and the checks that exercise it.

| Effective behavior | Owner | Verification |
| --- | --- | --- |
| Create, locate, list, and remove an isolated linked worktree while retaining its branch | Worktrunk 0.79.0 JSON commands | Real Worktrunk lifecycle test |
| Validate repository, branch, HEAD, registration, and worktree ownership | Rust coordinator using Worktrunk list and Git identity | Foreign and stale worktree cases |
| Explicit ignored-cache copy with a named source and include set | Worktrunk `copy-ignored` | Included and excluded cache fixture |
| Parse the approved private plan snapshot and run its locked launcher and timed probes | Rust coordinator | Preflight failure, mutation, and retry fixtures |
| Enforce private state permissions, immutable snapshots, atomic records, bounded recovery, and revision limits | Rust coordinator | State tamper, retry, and recovery fixtures |
| Run one model with the selected role, sandbox, native token budget, structured result, and JSON events | Official `codex exec` | Invocation fixtures and real model smoke |
| Supervise process groups, timeout, cancellation, output limits, heartbeat, and quiet observation | Rust coordinator | Timeout, cancellation, budget, and corrupt output fixtures |
| Capture staged, unstaged, and nonignored untracked files without changing the real index | Git temporary index, called by Rust | Full candidate and index-preservation fixtures |
| Validate writer write paths, inherited grants, image snapshots, original plan gates, and current review approval | Rust coordinator | Scope, image, evidence, reconciliation, and reviewer-setting fixtures |
| Create a reviewed checkpoint with normal Git hooks and an expected-parent branch update | Git primitives, called by Rust | Hook failure, mutation, stale tree, and parent-drift fixtures |
| Integrate the exact reviewed commit without losing nonconflicting target dirt | Git primitives, called by Rust | Exact-OID, dirty target, conflict, and drift fixtures |
| Independently inspect an exact candidate without write access | Rust review coordinator and official `codex exec` | Read-only review fixture and Sol smoke |
| Generate the portable plugin layout and pinned runtime packages | Nix generation and package expressions | Skill sync, Home Manager, plugin installation, and standalone portability gates |

Worktrunk's merge and push commands do not bind integration to a
caller-approved source commit OID. Git retains that operation. Automated
Worktrunk calls disable its hooks and commit-message generation; reviewed
checkpoints still run native Git hooks.

The .18 interfaces are:

```console
codex-improve execute PLAN REPOSITORY
codex-improve visual WORKTREE TREE DOSSIER --inputs MANIFEST
codex-improve review EXECUTION_ID TREE DOSSIER
codex-improve reconcile REVIEW_ID DOSSIER
codex-improve checkpoint EXECUTION_ID TREE --message 'type: summary'
codex-improve checkpoint EXECUTION_ID --integrate-oid CHECKPOINT_OID --target WORKTREE --expected-target TARGET_HEAD
```

The reviewed plan selects one of four writable lanes: economy, standard, deep,
or writer. Visual, scout, and reviewer are read-only. Visual imports original
images and collection evidence; it does not collect screenshots. Review reads
requirements from the original execution and accepts only current structured
evidence. Required originals and the inherited visual report reach the reviewer
as well as any executor that the plan names. Reconciliation records supported
finding dispositions without rewriting the raw review. `next` requires an
approved checkpoint. Approval does not grant commit, integration, push, or
publication authority; these remain separate user decisions.

The [review materials reference](../src/improve/references/closing-the-loop.md#review-dossier)
gives the accepted review and reconciliation JSON, image manifest and collection
provenance examples.

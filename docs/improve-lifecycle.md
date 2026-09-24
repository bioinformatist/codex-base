# Improve lifecycle ownership

The Improve runtime accepts plan contract `1.0.0-codex.17`. Earlier execution
artifacts stay in their legacy state namespace and are never migrated. The
following map records the behavior kept during the Worktrunk migration and the
check that exercises its new owner.

| Effective behavior | Owner | Verification |
| --- | --- | --- |
| Create, locate, list, and remove an isolated linked worktree while retaining its branch | Worktrunk 0.79.0 JSON commands | Real Worktrunk lifecycle test |
| Validate repository, branch, HEAD, registration, and worktree ownership | Python coordinator using Worktrunk list and Git identity | Foreign and stale worktree cases |
| Explicit ignored-cache copy with a named source and include set | Worktrunk `copy-ignored` | Included and excluded cache fixture |
| Parse the approved private plan snapshot and run its locked launcher and timed probes | Python coordinator | Preflight failure, mutation, and retry fixtures |
| Enforce private state permissions, immutable snapshots, atomic records, bounded recovery, and revision limits | Python coordinator | State tamper, retry, and recovery fixtures |
| Run one model with the selected role, sandbox, native token budget, structured result, and JSON events | Official `codex exec` | Invocation fixtures and real model smoke |
| Supervise process groups, timeout, cancellation, output limits, heartbeat, and quiet observation | Python coordinator | Timeout, cancellation, budget, and corrupt output fixtures |
| Capture staged, unstaged, and nonignored untracked files without changing the real index | Git temporary index, called by Python | Full candidate and index-preservation fixtures |
| Create a reviewed checkpoint with normal Git hooks and an expected-parent branch update | Git primitives, called by Python | Hook failure, mutation, stale tree, and parent-drift fixtures |
| Integrate the exact reviewed commit without losing nonconflicting target dirt | Git primitives, called by Python | Exact-OID, dirty target, conflict, and drift fixtures |
| Independently inspect an exact candidate without write access | Python review coordinator and official `codex exec` | Read-only review fixture and Sol smoke |
| Generate the portable plugin layout and pinned runtime packages | Nix generation and package expressions | Skill sync, Home Manager, plugin installation, and standalone portability gates |

Worktrunk's merge and push commands do not bind integration to a
caller-approved source commit OID. Git retains that operation. Automated
Worktrunk calls disable its hooks and commit-message generation; reviewed
checkpoints still run native Git hooks.

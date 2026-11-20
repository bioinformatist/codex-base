# Architecture

The checked-in `plugins/codex-base` tree is the distributable plugin. Portable
third-party skills are generated from pinned inputs. `src/improve` is the
first-party Codex adaptation of Improve; its scripts, config, schemas, and
references are copied into the generated Improve skill. Rust source, Cargo files,
tests and build outputs are excluded. `src/config-merge` provides the native
TOML 1.1 merge helper; it preserves values and comments with `toml_edit`,
allowing harmless formatting changes. The current execution
contract version is declared in `src/improve/SKILL.md`.

`src/docs-routing` is the canonical first-party documentation-routing skill.
`src/bend-proof` owns the optional Bend proof guidance and verified example;
target projects own their implementation, laws, proofs, and tests. Bend and
Lean are not bundled or installed by either distribution surface.
`src/benchmark-checklist`, `src/blast-radius`, and
`src/deprecation-and-migration` hold concise local MIT adaptations.
`nix/skills.nix` owns its deterministic construction alongside the other skills. The sync command
materializes that Nix output into the checked-in plugin and check mode compares
without writing. Both plugin and Home Manager consumers therefore use the same
files.

The portable plugin owns anonymous HTTP defaults for Context7 in `.mcp.json`; it contains no authenticated server or credentials.
Home Manager retains its local anonymous Context7 adapter and optional
per-user `context7_auth` adapter. Native Codex same-name configuration provides
the override boundary. Context7 connections receive only focused
public lookup terms, never private or secret content.

`nix/packages.nix` packages the default Codex CLI and Code Mode Host, Playwright CLI,
the static `codex-base-runtime` and config merge helper,
and `codex-improve` and `codex-doctor` wrappers that accept a Codex package. `nix/home-manager.nix` owns the full Linux runtime:
config overlay, MCP wrappers, global instructions, rules, packages, and direct
unnamespaced skill links. Its `package` option installs one CLI package and passes
that package's absolute `bin/codex` path to both helpers. The Improve wrapper
fixes that path before launching App Server through the project launcher, so launcher `PATH` changes
cannot select another CLI. The portable plugin still resolves `codex` from the
host `PATH`.

The desktop SSH client starts Codex App Server on the remote host. That process
can serve multiple chats, so installing a new binary and starting a new chat
does not necessarily replace it. Runtime updates and guidance reloads follow
[the reload instructions](../README.md#reload-after-an-update);
the desktop client and remote execution environment are separate installations.

Home Manager writes the base `AGENTS.md` first and appends nonempty
`programs.codexBase.extraInstructions` after a blank line to the user's global
guidance, which Codex loads for every project. The base stores persistent
per-user Git, Nix, secret-handling, evidence, and working preferences;
environment-specific policy such as proxy handling belongs in a consuming
module's extra instructions. The portable plugin does not install global
guidance. Executor prompts retain runner-local scope, checks, STOP, and handoff
constraints. Codex Base has no model-index or per-model global guidance files,
and its ordinary runtime default is Sol 6.2 with medium reasoning and verbosity.

Formal planning uses Astra 6.2 xhigh in native Plan Mode with callable context
management and structured questions. Independent plan review uses the same
model and effort and may use read-only Default Mode with both capabilities;
see the [workflow guide](workflow.md).

## Executor routing

Improve `.20` holds an official App Server process, connection and loaded
implementation root. Its private `codex-improve-v20` records retain task/native
IDs, workspace identity, plan/settings, candidate, usage and review summaries.
Codex owns full logs, agent dispatch, messages, waits and nested delegation.
`src/improve/config/roles.json` is the sole role source; native child role files
are derived from it, with instructions used as both native role descriptions
and developer instructions. Economy uses Luna low; standard/deep use Sol 6.2
medium/xhigh; writer/visual use Astra 6.2 xhigh; scout uses Sol 6.2 medium and
reports sources and evidence gaps; formal code review uses Astra 6.2 high.
All roles use medium verbosity. Writer stops affected work when missing or
conflicting facts prevent accurate writing and reports the gap. Required
unavailable models/efforts fail explicitly.

The implementation tree shares workspace-write authority and a native 300k
rollout budget. Scout/visual observation is a role convention inside that
boundary. A fresh formal read-only review root and descendants share an
independent 100k. Native hard enforcement is explicitly enabled. Same-task
continuation and revision keep the original loaded root; a connection/root loss
stops rather than cold-resuming or forking a new budget. Native cancellation,
timeouts and limits supply terminal outcomes; Improve has no root timer or
custom usage counter.

Formal review disables apps/plugins and GUI tools, allows only explicitly
reviewed existing MCP read tools, verifies inventory/annotations, and retains
native web and local image access. A filesystem sandbox does not establish MCP
authority. All external effects remain inside the user's task authorization.

Before capture, the client pages through descendants, interrupts active turns,
observes terminal states, terminates/re-lists background processes and rechecks
activity. It keeps the implementation root loaded and idle during independent
review. Unknown termination cannot approve. Git's temporary index captures the
complete candidate while preserving the real index. Write-path checks include
rename endpoints, deletions and type/mode changes; they are diff checks, not
per-path OS protection. Explicit protected metadata grants still apply.

Prefer host-managed worktrees and their returned paths. Git fills the CLI gap
with a detached worktree at the exact base. Common-dir, physical path, base and
task ownership are checked; ignored content is copied only with explicit
includes. Dirty, ignored, unknown-owned or symlinked worktrees cannot be removed.
The Nix closure supplies static Rust, Git, coreutils and selected Codex. Portable
users supply host tools; no Python/Cargo/Nix is needed by the static runtime.
Resources live beside the canonical executable prefix, optionally selected by
`CODEX_IMPROVE_SKILL_ROOT`. Original static PNG/JPEG inputs are privately
snapshotted and sent via native local-image inputs. Defaults are eight images,
20 MiB each and 50 MiB total, configurable by the reviewed plan. Verified
collection records bind candidate images; unbound observations cannot satisfy
acceptance.

Review binds the full plan, actual role/model/effort, task permissions/budget,
HEAD/tree, method, artifact bytes, images and integration target. Plan, candidate,
settings or evidence drift invalidates approval. Only normally completed valid
APPROVE with exact coverage permits an authorized checkpoint; integration also requires
the exact target HEAD and merge tree. Git owns hooks and expected-parent updates.
Historical records remain untouched without import or inherited approval.

The review schema, prompt and validation share `scope` plus `requiredEvidence`
and the plan's explicit deferred IDs. Native terminal status, bounded raw/parsed
reports, validation diagnostics, usage and approval are stored separately.
Cancellation saves cached reports after freeze and never grants approval; error
exits preserve cached diagnostics without RPCs. Missing `turn/completed` leaves
native status unknown and missing trustworthy final metering stays null.

A confirmed failed/interrupted implementation may reach independent review
after the same loaded-root, freeze, candidate, scope and current-evidence checks
as COMPLETE. Its implementation result remains intact. `dossier.notes` organizes
verified facts/sources, unresolved judgment and input changes. A review freezes
its predecessor and receives only the immediately preceding `previousReview`
snapshot plus a validated evidence summary; that context cannot approve a new
candidate.

See [lifecycle ownership](improve-lifecycle.md) for the responsibility/deletion
map, current CLI and remaining gaps.

## Pinned client evidence

The default CLI and Code Mode Host are 0.170.0, with Codex source pinned to
[`29eb79e9866b3262a777fdf8195c1b9e63684c91`](https://github.com/openai/codex/tree/29eb79e9866b3262a777fdf8195c1b9e63684c91).
The public [model catalog](https://github.com/openai/codex/blob/29eb79e9866b3262a777fdf8195c1b9e63684c91/codex-rs/models-manager/models.json)
and its UTF-8 `instructions_template` values have these SHA-256 digests:

| Public client input | SHA-256 |
|---|---|
| `models.json` | `d50b6749506d97e5f334dbabcb666eb1689f423cf3e88cfabdcf3c536b873068` |
| Sol 6.2 / Astra 6.2 `instructions_template` | `aa47d2dee261594c4944241b646088730d74d87afa4da8d2da0554540a5e7623` |
| Luna `instructions_template` | `e52174f354e3970ad8de5935fff8d04ddf2890a35659283d163befb56490198c` |

These identify public client templates. Remote effective templates, live model
capabilities and actual model behavior remain unverified. Feature flags and catalog
markers do not establish callable tools. This migration uses static and offline
checks; live behavior remains for observation during normal work. A downstream
package override and an actual deployment require their own verification.

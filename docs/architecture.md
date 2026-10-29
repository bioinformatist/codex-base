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
passes the path through the launcher to its worker, so launcher `PATH` changes
cannot select another CLI. The portable plugin still resolves `codex` from the
host `PATH`. Home Manager intentionally renders no Improve profile files.

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
and its ordinary runtime default remains Sol with medium reasoning.

Formal planning prerequisites and role selection are described in the
[workflow guide](workflow.md). The coordinator reads the selected role from
`src/improve/config/roles.json` independently of the main session's model and
stores its effective settings with each execution; it does not load Codex profiles.

## Executor routing

Improve `.19` uses the public `codex-improve` coordinator and private state in
`codex-improve-v19`. It rejects older contracts without migrating or resuming
old tasks. Every plan declares environment, routing, and gate blocks; an
explicit CLI lane must agree with the plan.

The reviewed plan selects a writable lane; scout, visual, and reviewer are
read-only. See [execution lanes](workflow.md#execution) for their conditions.
Actual Git differences are checked against write paths through execution,
follow-up, review, and checkpoint; this is a diff check rather than per-path OS
protection. Protected roots retain their explicit-grant rules.

The Nix closure supplies the static Rust runtime, Git, Codex and Worktrunk.
Portable users install the matching precompiled runtime and supply the host tools.
The runtime locates resources under its canonical executable prefix;
`CODEX_IMPROVE_SKILL_ROOT` can select another matching skill layout.
No Python interpreter or image package is needed at runtime. Native `--image` carries bounded static PNG/JPEG originals from
private snapshots. The caller supplies and verifies collection records for
candidate images; unbound observations cannot satisfy a candidate gate. Image
limits default to eight inputs, 20 MiB each and 50 MiB total; a reviewed plan
may override them. Images and private paths stay out of ordinary metrics.

Review binds the original plan, role, grants, exact candidate, method, reviewer
settings, and required evidence. A new review invalidates the preceding
approval. Reconciliation retains the original result and records supported
finding dispositions. Changed support artifacts invalidate approval reuse.
Checkpoints require current matching approval; integration also binds the
caller-verified target HEAD and precomputed merge tree. Worktrunk manages
worktrees and Git owns candidate and checkpoint operations. The coordinator
does not probe quota, switch models, or replay started calls. The plugin changes
neither the main model nor native Codex configuration.

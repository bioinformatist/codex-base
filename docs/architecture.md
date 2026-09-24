# Architecture

The checked-in `plugins/codex-base` tree is the distributable plugin. Portable
third-party skills are generated from pinned inputs. `src/improve` is the
first-party Codex adaptation of Improve; its scripts, config, schemas, and
references are copied into the generated Improve skill. The current execution
contract version is declared in `src/improve/SKILL.md`.

`src/docs-routing` is the canonical first-party documentation-routing skill.
`nix/skills.nix` owns its deterministic construction alongside the other skills. The sync command
materializes that Nix output into the checked-in plugin and check mode compares
without writing. Both plugin and Home Manager consumers therefore use the same
files.

The portable plugin owns anonymous HTTP defaults for Mintlify Index and
Context7 in `.mcp.json`; it contains no authenticated server or credentials.
Home Manager retains its local anonymous Context7 adapter and optional
per-user `context7_auth` adapter. Native Codex same-name configuration provides
the override boundary. Both public third-party services receive only focused
public lookup terms, never private or secret content.

`nix/packages.nix` packages Codex, its Code Mode Host companion, Playwright CLI,
and the single `codex-improve` wrapper with Python, Git, and Worktrunk. `nix/home-manager.nix` owns the full Linux runtime:
config overlay, MCP wrappers, global instructions, rules, packages, and direct
unnamespaced skill links. It intentionally renders no Improve profile files.

The desktop SSH client starts Codex App Server on the remote host. That process
can serve multiple chats, so installing a new binary and starting a new chat
does not necessarily replace it. Runtime updates and guidance reloads follow
[the reload instructions](../README.md#reload-after-an-update);
the desktop client and remote execution environment are separate installations.

The managed global `AGENTS.md` stores persistent per-user Git, Nix, proxy,
secret-handling, evidence, and working preferences. The portable plugin does
not install it. Executor prompts retain runner-local scope, checks, STOP, and
handoff constraints. Codex Base has no model-index or per-model global guidance
files, and its ordinary runtime default remains Sol with medium reasoning.

Native context-management eligibility depends on live tools and server
capability for the signed-in account. In the desktop app, that task is a Codex chat under a
project; entering Plan Mode or invoking Improve in an existing chat does not
start another session. Codex Base therefore keeps Sol as its ordinary default.
Formal Improve planning requires a session that actually exposes context
management and structured questions. Astra is an explicit choice for difficult
planning; its name is not capability evidence.

In the CLI, ordinary `/model` selection changes the current chat and attempts
to persist defaults. `/new` uses effective defaults plus explicit launch
settings, rather than simply copying the current chat's model. Codex 0.155.1
preserves a launch-model override across those `/new` chats. A user who keeps
Sol as the persistent default can start a one-off Astra invocation with
`codex -m gpt-6-astra`; Codex Base does not ship an Astra runtime profile.
The [configuration guide](configuration.md#model-choice) records the scope
distinctions and pinned source evidence.

Formal Improve planning uses built-in Plan Mode only when the live session
exposes native context management and structured questions. It produces one
complete replacement in chat and creates no plan, questionnaire, handoff, or
temporary file. A later authorized writable phase may persist that result.
For temporary native-context-management unavailability, a user may explicitly
grant the [per-plan waiver](../README.md#temporary-context-waiver) for one named
plan and its same-scope review. This does not change the global prerequisites.
Implementation, audits, and routine lifecycle bookkeeping remain available in
Default Mode without starting a new planning workflow.

The historical prompt comparison for Codex 0.153.4 is limited to the public
templates in `models-manager/models.json` at revision
`3d2ee51ca2d5db578f328aa75e20aa22c0197c9a`: Sol, Terra, and Luna share that
public base/template content, while Astra differs. It does not describe the
current release pin or undisclosed server-side instructions, and Codex Base
does not copy those model prompts.

Improve reads the selected role from `src/improve/config/roles.json` and stores
its effective settings with each execution. It never looks up a Codex profile.

## Executor routing

Improve `.17` uses the public `codex-improve` coordinator. A reviewed plan
selects economy (Luna/low), standard (Sol/medium), or deep (Sol/xhigh). Scout
uses Luna/high; correctness and elegance review use Sol/high. The coordinator
reads the launcher and probes from the plan, snapshots the selected role, and
runs one model call. It does not probe quota, switch models, or replay failures.
The Nix closure supplies Python 3.11 or newer, Git, Codex, and Worktrunk. A
portable plugin install requires these host commands. Worktrunk manages
worktrees; Git owns exact candidate and checkpoint operations. The plugin
changes neither the user's main model nor native Codex configuration.

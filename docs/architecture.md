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
and thin runner wrappers. `nix/home-manager.nix` owns the full Linux runtime:
config overlay, MCP wrappers, global instructions, rules, packages, and direct
unnamespaced skill links. It intentionally renders no Improve profile files.

The managed global `AGENTS.md` stores persistent per-user Git, Nix, proxy,
secret-handling, evidence, and working preferences. The portable plugin does
not install it. Executor prompts retain runner-local scope, checks, STOP, and
handoff constraints. Codex Base has no model-index or per-model global guidance
files, and its ordinary runtime default remains Sol with medium reasoning.

Formal Improve planning uses built-in Plan Mode only when the live session
exposes native context management and structured questions. It produces one
complete replacement in chat and creates no plan, questionnaire, handoff, or
temporary file. A later authorized writable phase may persist that result.
Implementation, audits, and routine lifecycle bookkeeping remain available in
Default Mode without starting a new planning workflow.

Prompt compatibility statements for Codex 0.153.4 are limited to the public
templates in `models-manager/models.json` at revision
`3d2ee51ca2d5db578f328aa75e20aa22c0197c9a`: Sol, Terra, and Luna share that
public base/template content, while Astra differs. This boundary says nothing
about undisclosed server-side instructions, and Codex Base does not copy those
model prompts.

Improve profile names remain stable labels in roles, manifests, metrics, and
handoffs. Runners pin effective settings at CLI precedence and never look up a
Codex profile.

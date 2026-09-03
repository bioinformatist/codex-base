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

Improve profile names remain stable labels in roles, manifests, metrics, and
handoffs. Runners pin effective settings at CLI precedence and never look up a
Codex profile.

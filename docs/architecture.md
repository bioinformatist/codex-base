# Architecture

The checked-in `plugins/codex-base` tree is the distributable plugin. Portable
third-party skills are generated from pinned inputs. `src/improve` is the
first-party Codex adaptation of Improve 1.0.0-codex.14; its scripts, config,
schemas, and references are copied into the generated Improve skill.

`nix/skills.nix` owns deterministic skill construction. The sync command
materializes that Nix output into the checked-in plugin and check mode compares
without writing. Both plugin and Home Manager consumers therefore use the same
files.

`nix/packages.nix` packages Codex, its Code Mode Host companion, Playwright CLI,
and thin runner wrappers. `nix/home-manager.nix` owns the full Linux runtime:
config overlay, MCP wrappers, global instructions, rules, packages, and direct
unnamespaced skill links. It intentionally renders no Improve profile files.

Improve profile names remain stable labels in roles, manifests, metrics, and
handoffs. Runners pin effective settings at CLI precedence and never look up a
Codex profile.

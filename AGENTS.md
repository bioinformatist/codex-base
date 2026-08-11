# codex-base contributor guidance

This repository distributes a Codex-only plugin and a Nix Home Manager module.
Keep the plugin portable and keep host-specific integration outside this
repository.

- Treat `src/improve` as the editable Improve source. Generate
  `plugins/codex-base/skills` with `nix run .#sync-vendored-skills`; never edit
  generated skills directly.
- Run `nix run .#sync-vendored-skills -- --check` before builds and run
  `nix flake check --allow-import-from-derivation` before handoff.
- Preserve the pinned upstream revisions and inspect every generated diff.
- Never add credentials, user names, host names, absolute home paths, or Nix
  store paths to distributable files.
- Keep Improve profile strings as compatibility identifiers, but do not add
  runtime profile files or profile lookup.
- Do not publish, deploy, install into a real home, or update downstream
  configurations without separate authorization.

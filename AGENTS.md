# codex-base contributor guidance

This repository distributes a Codex-only plugin and a Nix Home Manager module.
Keep the plugin portable and keep host-specific integration outside this
repository.

- Treat `src/improve` as the editable Improve source. Generate
  `plugins/codex-base/skills` with `nix run .#sync-vendored-skills`; never edit
  generated skills directly.
- Before implementation or handoff, read [Checks](CONTRIBUTING.md#checks)
  for first-principles verification, impact-based local checks, evidence reuse,
  and full integration gates. Instruction changes count as behavior changes;
  a Markdown extension alone does not qualify for prose-only checks.
- Preserve the pinned upstream revisions and inspect every generated diff.
- Never add credentials, user names, host names, absolute home paths, or Nix
  store paths to distributable files.
- Keep Improve role settings in `src/improve/config/roles.json`; the .17
  coordinator snapshots the selected role and does not load Codex profiles.
- Do not publish, deploy, install into a real home, or update downstream
  configurations without separate authorization.

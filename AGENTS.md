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

## Release notes

- Write changelog entries and GitHub release notes from the diff since the
  previous release: notable user-visible changes and upgrade actions newly
  required by those changes. Previous notes are history, not a template.
- Include dependency or runtime updates only when they have a notable user
  impact; describe that impact rather than listing version bumps.
- Keep unchanged contracts and options, routine setup or reload instructions,
  architecture background, and verification records in their existing docs or
  PRs. Omit generic disclaimers about performance, token savings, or accuracy
  when the notes make no such claim.
- Include compatibility warnings or limitations only when needed to understand
  a concrete change or qualify a claim made in the notes. Apply the same
  selection to English and Chinese, and remove empty sections.

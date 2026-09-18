# Updating pinned inputs

## Applying an update

For a Git-backed plugin installation, refresh the configured marketplace on
the execution host:

```console
codex plugin marketplace upgrade bioinformatist-codex
```

This refreshes the marketplace snapshot and installed plugin cache; it does
not install or upgrade the Codex executable. Nix/Home Manager users instead
update the consuming configuration's locked `codex-base` input, review its diff,
and activate that configuration. Updating this repository or its lock alone
does not update a user's installed environment.

Then follow [Reload after an update](../README.md#reload-after-an-update).

## Vendored and root inputs

Update one pinned input at a time. Read its license and complete relevant diff,
then update `vendor/sources.json`, the flake input or fixed-output package, and
any exact Codex adaptation together.

Run the generator in write mode, inspect all changes under
`plugins/codex-base/skills`, then run:

```console
nix run .#sync-vendored-skills -- --check
nix flake check --allow-import-from-derivation
```

Root input updates require manual semantic review; Renovate must not auto-merge
them. Improve role values, schemas, protected-path behavior, and compatibility
fixtures are one compatibility boundary and must change together.

## Codex releases

This repository owns the Codex and Code Mode Host release pins. The dedicated
`maintenance-codex.yml` workflow reads GitHub's published SHA-256 digests and
updates both Linux musl binaries, the matching `codex-src` tag and lock entry,
and the English and Chinese README versions atomically. It always uses the fixed `maint/codex`
branch and a pull request to `main`; it does not weaken Renovate's manual-review
policy for vendored or root inputs.

The workflow requires a repository-scoped secret named `MAINTENANCE_PAT`.
Repository rules must keep `main` pull-request-only and require the strict
`check` and `plugin-portability` statuses, with zero approvals and no bypass.
Record only these names in repository documentation, never credential values.

CI runs on pull requests and can be dispatched manually; it does not rerun on
branch, main or tag pushes. Before publishing a release or updating a downstream
lock, verify that the landed Git tree matches the tree covered by the passing
PR checks and that relevant build inputs are unchanged. Reuse that evidence;
do not require a second full run solely because the merge has a new commit ID.
If the evidence or tree identity is missing or differs, manually dispatch CI
for the target ref and require both jobs to pass. See
[the integration gate](../CONTRIBUTING.md#integration-gate).

For a manual source update, begin from a clean checkout and run:

```console
scripts/update-codex-release
nix run .#sync-vendored-skills -- --check
nix flake check --allow-import-from-derivation
```

The updater accepts `--release-json PATH` for deterministic local fixtures. It
may change only `README.md`, `README.zh-CN.md`, `flake.nix`, `flake.lock`, and
`nix/packages.nix`. Each README must contain exactly one stable release sentence;
the updater replaces only its Codex version token and fails before editing if
either localized sentence is missing, duplicated, or malformed.

Configuring `MAINTENANCE_PAT`, activating the repository ruleset, and manually
dispatching the real workflow are post-integration acceptance tasks. They are
not part of source implementation or worktree verification.

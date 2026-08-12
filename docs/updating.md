# Updating pinned inputs

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
and the README version atomically. It always uses the fixed `maint/codex`
branch and a pull request to `main`; it does not weaken Renovate's manual-review
policy for vendored or root inputs.

The workflow requires a repository-scoped secret named `MAINTENANCE_PAT`.
Repository rules must keep `main` pull-request-only and require the strict
`check` status, with zero approvals and no bypass. Record only these names in
repository documentation, never credential values.

For a manual source update, begin from a clean checkout and run:

```console
scripts/update-codex-release
nix run .#sync-vendored-skills -- --check
nix flake check --allow-import-from-derivation
```

The updater accepts `--release-json PATH` for deterministic local fixtures. It
may change only `README.md`, `flake.nix`, `flake.lock`, and `nix/packages.nix`.

Configuring `MAINTENANCE_PAT`, activating the repository ruleset, and manually
dispatching the real workflow are post-integration acceptance tasks. They are
not part of source implementation or worktree verification.

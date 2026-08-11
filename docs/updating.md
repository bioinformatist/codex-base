# Updating vendored inputs

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

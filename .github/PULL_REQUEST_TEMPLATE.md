## Summary

Describe the user-visible or maintenance outcome and the surfaces it changes.

## Verification

- [ ] `nix run .#sync-vendored-skills -- --check`
- [ ] `nix flake check --allow-import-from-derivation`
- [ ] `tests/plugin-portability.bash` when Improve runners or Codex invocation changed
- [ ] Generated diffs, bilingual docs, and SVG renders reviewed when applicable
- [ ] No credentials, private identifiers, absolute home paths, or Nix store paths added

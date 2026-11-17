# Updating pinned inputs

## Applying an update

> [!WARNING]
> Finish active Improve tasks before updating. New tasks accept only `.20` plans;
> historical records remain untouched without continuation or inherited approval.

For a Git-backed plugin, refresh the marketplace on the execution host:

```console
codex plugin marketplace upgrade bioinformatist-codex
```

This updates the marketplace snapshot and installed plugin cache, not Codex.
Nix/Home Manager users update the consuming configuration's locked `codex-base`
input, review its diff and activate it separately. Repository edits alone do not
change installed environments. Portable Improve also needs the matching native
runtime archive, checksum and source metadata; see [installation](../README.md#codex-plugin).
Then [reload the execution runtime](../README.md#reload-after-an-update).

## Vendored and root inputs

Updates are manual. Inspect the source, license and relevant diff, then update
`vendor/sources.json`, selected flake/package pins and exact adaptations together.
Edit canonical sources, run sync, inspect every generated diff, then check:

```console
nix run path:.#sync-vendored-skills -- --check
nix flake check path:. --allow-import-from-derivation
```

`path:.` includes new untracked files without staging. Runtime/configuration,
roles, schemas, permissions and current-behavior fixtures must agree. Relevant
standalone portability remains required by [CONTRIBUTING](../CONTRIBUTING.md#checks).

## Codex releases

Check official stable releases during authorized maintenance. Update the source
tag/lock, CLI and Code Mode Host versions and fixed hashes in `nix/packages.nix`,
and both README version sentences atomically. Keep the source/CLI/host consistency
check; there is no updater or dedicated update PR workflow. Do not refresh
unrelated inputs. Verify actual selected executables, including a Home Manager
package override, rather than inferring installed state from repository pins.

CI still uses upstream Nix with nix-command/flakes. Its PR/manual `check` and
`plugin-portability` jobs, concurrency cancellation, read-only repository
permission and runtime artifacts remain the integration gate. Before release or
downstream use, reuse exact passing tree/input evidence or dispatch the required
CI with separate authority; a pending job is not a pass.

## Selected package maintenance

- GitHub MCP 2.1.0 uses a fixed source/vendor override until nixpkgs-tools supplies
  that version or newer with the required toolsets/schema and authentication.
- Context7 4.7.0 comes from the selected nixpkgs-tools pin. Research preview stays
  off; local anonymous, authenticated wrapper and hosted endpoints are separate
  acceptance surfaces.
- mcp-nixos 3.1.0 uses upstream `lib.mkMcpNixos` with the base package set, keeping
  FastMCP 4 / MCP 2 scoped to that server. The newer tools set exposes an upstream
  MCP-types recursion; [Issue #83](https://github.com/bioinformatist/codex-base/issues/83)
  tracks the product need. Revisit selection when the newer path evaluates and
  passes build/protocol checks; do not replace the whole Python set.
- Playwright CLI/skill is 0.1.24 on Node 24. Its underlying Playwright is
  `1.66.0-alpha-1794252756000`; the CLI's release status does not make that a stable
  browser dependency. Keep headless, isolated sessions and explicit download
  authority when checking upgrades.

## Retired automation and installations

Source removes the dedicated maintenance workflow/updater, Renovate entry,
ADHX and Worktrunk integration. This does not disable remote services or rewrite
existing installations. On 2026-11-16 the repository's remote CI and Maintain
Codex Release workflows were still active. No open Renovate PRs were found;
Renovate app installation remains unverified. The one inspected host had no
Codex Base marketplace registration; other installations were not inspected.

After authorized integration, the owner must confirm retirement of remote
maintenance scheduling and the bot/app, and review any mutable-branch marketplace
registrations before updating installations. A Git marketplace follows its
configured source; updating a mutable branch can change cached skills. This
implementation neither pins nor updates an existing registration. Home Manager
locks and package overrides remain separate inheritance paths. No remote bot,
real Home, host or downstream configuration was changed by source implementation.

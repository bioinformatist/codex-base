# Contributing to Codex Base

Thank you for helping improve Codex Base. This repository ships two related
surfaces: a portable Codex plugin and a Linux Nix/Home Manager environment.
Keep their ownership boundaries explicit in code, tests, and documentation.

## Development environment

Enter the locked contributor environment before making changes:

```console
nix develop
```

The shell contains the tools used by the repository checks, including Codex,
Git, shellcheck, actionlint, typos, PyYAML, and the SVG renderer.

## Editable and generated files

`src/improve` is the editable Improve source, and `src/docs-routing` is the
editable documentation-routing source. The skills under
`plugins/codex-base/skills` are generated from that source and pinned upstream
inputs; do not edit them directly. Regenerate them with:

```console
nix run .#sync-vendored-skills
```

Inspect every generated diff and preserve the pinned upstream revisions. Never
add credentials, private host names, user names, absolute home paths, or Nix
store paths to distributable files.

Keep anonymous plugin MCP defaults in `plugins/codex-base/.mcp.json`. Keep
Home Manager's local and optional authenticated adapters in
`nix/home-manager.nix`; never copy credentials or authenticated configuration
into the portable plugin.

## Checks

Run the complete repository gate before opening a pull request:

```console
nix run .#sync-vendored-skills -- --check
nix flake check --allow-import-from-derivation
```

If a change affects the plugin manifest, `.mcp.json` or MCP behavior, the
installed plugin layout, or Improve runners or their Codex invocation, also run
the standalone non-Nix installation path:

```console
tests/plugin-portability.bash
```

The Nix checks do not replace this standalone path.

The checks do not replace review of public prose, translation accuracy, SVG
rendering, or generated diffs.

## Public documentation and assets

Keep `README.md` and `README.zh-CN.md` semantically equivalent. Update both
capability catalogs together and preserve their row IDs and order. When the
Codex release pin changes, use `scripts/update-codex-release`; the two README
version sentences and all release pins are one atomic update.

The SVG files are their own editable sources. When changing the logo or workflow
diagram, update the matching brief under `docs/assets/prompts`, render the
required small and large previews locally, and do not commit raster previews.
Do not use borrowed brand marks or external image dependencies.

## Maintainer references

- [Architecture and ownership boundaries](docs/architecture.md)
- [Pinned-input and Codex release updates](docs/updating.md)
- [Bundled source credits](docs/credits.md)

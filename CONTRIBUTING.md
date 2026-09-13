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

### Local verification

Work from first principles: name the failure each check is meant to catch,
run the smallest check that can decide whether the change works, then complete
the checks required by its impact. Select by changed meaning and dependencies,
not file extensions.

| Change | Required local verification |
|---|---|
| Ordinary prose, translations, or static assets without behavior changes | Relevant documentation checks; review facts, links, translations, and rendering as applicable |
| Agent instructions, skills, prompts, or planning contracts | Targeted scenarios for changed behavior, including permission and STOP boundaries where affected; Markdown is not a prose-only exemption |
| An isolated check or documentation assertion | Run that check and relevant negative cases; verify affected Nix evaluation when changing Nix expressions |
| Runners, invocation, or plugin layout and behavior | Affected behavior regressions and the standalone portability path when triggered below |
| Dependency pins, shared build logic, cross-layer changes, or uncertain impact | The full repository gate below, plus any affected standalone checks |

For documentation changes, select the relevant existing checks from
`docs-contract`, `typos`, and `stale-wording`. For example:

```console
nix build --no-link .#checks.x86_64-linux.docs-contract
```

When editable or generated skills, their generator, or pinned skill inputs
change, run `nix run .#sync-vendored-skills -- --check` before building and
inspect the generated diff.

If a change affects the plugin manifest, `.mcp.json` or MCP behavior, the
installed plugin layout, or Improve runners or their Codex invocation, also run
the standalone non-Nix installation path:

```console
tests/plugin-portability.bash
```

The Nix checks do not replace this standalone path.

The checks do not replace review of public prose, translation accuracy, SVG
rendering, or generated diffs.

Record the tested revision and local delta, or the exact candidate tree, with
commands, results, and omitted checks. Reuse a previous result only when the
check's relevant inputs and environment are demonstrably unchanged; otherwise
rerun it. A worktree name alone is not evidence. A scoped local handoff may
finish without the full suite, but must say so; pending or unrun checks are not
passed checks.

### Integration gate

Before merging, require the full Nix and standalone portability CI gates to
pass for the exact candidate being integrated. CI runs both on pull requests
and pushes. If CI cannot supply these results, run both locally before
integration. A local full-suite rerun is not required solely to open a pull
request or hand off scoped work.

The full Nix gate is:

```console
nix run .#sync-vendored-skills -- --check
nix flake check --allow-import-from-derivation
```

Existing release requirements and explicit gates in an approved plan remain
binding unless the user approves an amendment. Local verification does not
authorize integration, publication, deployment, or changes to those gates.

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

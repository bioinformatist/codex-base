# Visual assets

The SVG files are editable sources with no external images, fonts, raster
sources, or borrowed brand marks. Each English diagram has a Simplified Chinese
peer with the same topology:

- `codex-base-workflow.svg` and `codex-base-workflow.zh-CN.svg`: overview.
- `codex-base-routing.svg` and `codex-base-routing.zh-CN.svg`: execution lanes.
- `codex-base-verification.svg` and `codex-base-verification.zh-CN.svg`: verification paths.
- `../../plugins/codex-base/assets/codex-base.svg`: packaged plugin mark.
- `prompts/`: design intent and maintenance instructions for each asset.

After editing, validate the XML and render temporary previews with
`rsvg-convert`. Inspect all six diagrams at 1200 px and 720 px wide and the
logo at 256 px and 24 px. Do not commit PNG previews.

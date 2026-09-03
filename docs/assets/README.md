# Visual assets

The SVG files in this repository are code-native editable sources. They use no
external images, fonts, generated raster source, or borrowed brand marks.

- `codex-base-workflow.svg` is the English README overview.
- `codex-base-workflow.zh-CN.svg` is its Simplified Chinese peer, with the same
  geometry, palette, order, and product claims.
- `../../plugins/codex-base/assets/codex-base.svg` is the packaged plugin mark.
- `prompts/` records the design intent and reproduction procedure for each.

After editing, validate the XML and render temporary previews with
`rsvg-convert`. Check both workflow variants at 1200 px and 720 px wide and the
logo at 256 px and 24 px. Do not commit the PNG previews.

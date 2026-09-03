# Codex Base logo design brief

## Objective and audience

Create a restrained, code-native mark for developers discovering Codex Base in
the plugin listing and README. It should suggest branching work, review, and a
completed checkpoint without copying any vendor identity.

## Labels and branch meaning

The logo contains no text. A shared start node branches to a review node and a
checked checkpoint node. The check indicates an explicit verified boundary,
not guaranteed correctness or safety.

## Layout and palette

Use a square `0 0 64 64` viewBox, rounded dark paths, white intermediate nodes,
and one blue accent (`#2563eb`) for the checked endpoint. Keep the silhouette
recognizable at 24 px and balanced at 256 px. Use no gradients or shadows.

## Accessibility and prohibited content

Include `role="img"`, a `<title>`, and a `<desc>`. Do not use text, model names,
mascots, borrowed logos, private identifiers, dates, benchmarks, external
images, hosted fonts, or guaranteed-safety claims.

## Output and update procedure

Edit `plugins/codex-base/assets/codex-base.svg` directly. Parse it as XML, then
render temporary 256 px and 24 px PNGs with `rsvg-convert`. Inspect the branch,
node spacing, and check silhouette at both sizes. Update this brief whenever the
meaning, layout, palette, or constraints change; never commit raster previews.

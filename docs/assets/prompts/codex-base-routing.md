# Execution lane diagram brief

Show the approved plan selecting economy, standard, deep, or writer, with
current models, effort levels, and conditions. Economy uses `gpt-6-luna` / low;
standard and deep use `gpt-6.2-sol` / medium and xhigh. Writer and visual use
`gpt-6.2-astra` / xhigh; scout uses `gpt-6.2-sol` / medium. All use medium
verbosity. Writer stops only the affected work and reports the gap when missing
or conflicting facts prevent accurate writing. Scout reports sources and
unresolved evidence gaps. Scout and visual observe within shared team
permissions; formal review uses a separate read-only `gpt-6.2-astra` / high root.
Roles do not automatically switch or fall back.

Keep English and Chinese topology equivalent on a 1200 × 620 canvas, using
the workflow palette, system fonts, real text, `role="img"`, and localized
title and description. Use no external assets. After candidate capture, parse
both SVGs, render each at 1200 and 720 px with the locked `rsvg-convert`, and
retain real invocation logs and candidate/image hashes for independent review
of labels, overlap, clipping, and readability. Keep PNGs private.

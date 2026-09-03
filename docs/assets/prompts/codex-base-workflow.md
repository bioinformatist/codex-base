# Codex Base workflow design brief

## Story and exact labels

Show why a small, clear task should be edited directly and where avoidable usage appears as a task grows. The ordinary lane is `Small, clear task` → `Edit directly` → `As the conversation grows, decisions stay only in context` → `Rereading, drift, and rework can consume avoidable usage`. The Chinese lane is `小而明确的任务` → `直接修改最快` → `任务变长后，关键决定仍只留在上下文里` → `反复读取、做偏和返工会继续消耗用量`.

Use `Reduce avoidable usage on long tasks` as the English title and `让长任务少浪费用量` as the Chinese title. The Chinese caveat is `规划和审查也会消耗用量；小而明确的任务通常直接修改更合适。`

The Codex Base lane is `Clarify intent and write decisions down` → `Verify current documentation` → `Choose the execution lane in the plan`. It branches to `Settled + deterministic` / `Spark · separate usage limits` or `Complex or high-risk` / `Standard / Deep`, rejoins at `Verify and simplify each step`, optionally visits `Add specialist review` when risk warrants, and rejoins at `Leave a resumable checkpoint`. End with `Less repeated context. Earlier correction. Less avoidable usage.`

The Chinese labels convey the same actions with language-specific line breaks: `问清楚，并把关键决定写下来`, `查证当前版本的文档`, `在计划中选择执行通道`, `边界和检查都明确` / `Spark · 使用独立的用量限制`, `复杂或高风险` / `Standard / Deep`, `每一步先验证，再删繁就简`, `追加专项审查`, `留下可以继续的检查点`, and `少重复读取长上下文，少在错误方向上继续消耗。`

Name both mechanisms: eligible Spark routing preserves main-model capacity because Spark has its own usage limits, while early persistence and checks reduce avoidable context reconstruction and rework. Link the public prose to <https://learn.chatgpt.com/docs/agent-configuration/speed>. Do not claim lower price, fewer tokens, guaranteed total savings, automatic routing, or universal Spark access. State that planning and review add overhead and direct editing usually wins for a small, clear task.

## Topology, layout, and maintenance

Both SVGs share the same non-text structure. Every ordinary node continues to its explicit outcome. Both executor branches rejoin before per-step verification. Optional correctness/elegance review and the direct path both enter the final checkpoint, which leads to the outcome. Full-Nix documentation lookup is conditional on availability but remains forward-only.

Keep the `0 0 1200 720` viewBox, high-contrast slate/blue/amber/green palette, real text, `role="img"`, localized `<title>` and `<desc>`, and system fallbacks including `Segoe UI`, `Noto Sans CJK SC`, and `Microsoft YaHei`. Do not add external assets, hosted fonts, raster sources, or generators.

Parse both files as XML. Render each at 1200 px and 720 px with `rsvg-convert` through the repository devShell, then inspect all four PNGs for clipping, overlap, broken branches, and illegible labels. Keep previews temporary and update both SVGs and this brief together.

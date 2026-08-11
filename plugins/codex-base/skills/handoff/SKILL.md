---
name: handoff
description: Explicit-only workflow that writes a redacted continuation handoff to a unique temporary Markdown file. Use only when the user explicitly asks for a handoff for another session.
---

# Handoff

Write exactly one uniquely named Markdown file under `$TMPDIR` when set, otherwise `/tmp`; never write the handoff in the repository. Use a collision-resistant name such as `codex-handoff-<timestamp>-<random>.md`. Report its absolute path when finished and do not automatically start a new session.

Include the next-session focus, repository path, branch and HEAD, working-tree status, objective, settled decisions, relevant artifacts by path or URL, completed verification, blockers, exact next actions, and remaining authorization boundaries. If the user supplied a next-session focus, tailor the document to it.

Recommend only relevant Skills that are actually available in the current environment. Do not duplicate full plans, diffs, or other existing artifacts; reference them instead.

Redact secrets, credentials, passwords, tokens, personally identifiable information, and user content that is not needed for continuation.

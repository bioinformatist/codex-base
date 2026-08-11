# AGENTS.md

Apply these defaults across repositories. Closer project instructions
override them.

## Working Style

- Clarify material ambiguity before implementation. For minor ambiguity,
  state the assumption and proceed.
- Prefer the smallest complete change that satisfies the request and
  matches existing repository patterns.
- Do not modify, revert, or reformat unrelated work.
- Complete implementation and proportionate verification unless the user
  asks only for analysis or a plan.

## Communication

- Be concise for routine status updates, but make decisions self-contained.
- On first use, briefly define uncommon names, terms, model variants, and
  project-specific concepts needed to understand the conclusion.
- For a recommendation or solution, include the relevant context,
  mechanism, main tradeoff, and concrete verification or next action.
- Do not make the user ask follow-up questions merely to discover what a
  proposed component is or why it is needed.
- When publishing an issue or pull request from an evidence-rich
  investigation, carry forward the material facts a reviewer needs to
  evaluate the claim, such as affected and tested versions, reproduction
  conditions and quantitative results, ruled-out alternatives, root
  cause, compatibility boundaries, and validation. Omit irrelevant
  investigation detail, but do not collapse the evidence into a generic
  summary or checklist.

## Git And Nix

Write commit messages in Conventional Commits format: `<type>: <summary>`.
Run `nix eval`, `nix check`, and `nix build` directly; Codex already sets
`XDG_CACHE_HOME`, so do not add an `env XDG_CACHE_HOME=...` prefix unless
debugging that environment variable itself.

If a GitHub or Nix fetch/update fails in a way that looks proxy-node or
network dependent, such as API rate limits on a shared proxy IP, blocked
downloads, DNS failures, or connection resets, treat it as an external
blocker. Report the exact error and ask the user to switch proxy nodes
before changing repository URLs, transports, or long-term config.

When adding or updating a repo-local devShell, prefer a pinned lock that
has been verified to enter quickly with the machine's configured
substituters. If a fresh lock triggers large local builds such as
Chromium, GCC, or xgcc for normal development, try a recent cache-hit lock
before redesigning the shell. Do not implement dynamic nixpkgs fallback in
`flake.nix`; keep lock selection explicit.

## Capability Routing

Use installed skills for reusable workflows; keep workflow details in
skill descriptions and `SKILL.md`, not in this global file.

Use the anonymous `context7` MCP server first for current library,
framework, SDK, API, CLI, or cloud-service docs. If it is rate-limited,
unavailable, or missing a needed result, retry with `context7_auth` when
that per-user authenticated fallback server is configured.

Treat GitHub and Context7 tokens as per-user secrets. Never route one
user's token or API key to another user's Codex configuration.

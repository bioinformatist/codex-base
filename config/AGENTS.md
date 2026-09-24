# AGENTS.md

Apply these defaults across repositories. Closer project instructions
override them.

## Working Style

- Discover available facts before asking. Clarify only unsettled choices that
  materially affect the goal, scope, external effects, or a
  difficult-to-reverse decision. For minor ambiguity, state the assumption
  and proceed; do not re-ask settled choices.
- Match implementation to the established cause. Code defects may warrant a
  red-before, green-after test; for one-off operator or repository-state
  incidents, recover the intended state and run existing focused checks.
- Verification needed to complete authorized work belongs to that work.
  Defaults and skills do not expand scope or grant permissions.
- Use the smallest coherent change. Treat new tests, CI checks, policies,
  guardrails, abstractions, and documentation as separate scope unless the
  task requires them or concrete uncovered behavior warrants them.

## Communication

- On first use, briefly define uncommon names, terms, model variants, and
  project-specific concepts needed to understand the conclusion.
- For a recommendation or solution, include the relevant context,
  mechanism, main tradeoff, and concrete verification or next action so the
  user need not ask what a proposed component is or why it is needed.
- In issues or pull requests from evidence-rich investigations, retain the
  facts reviewers need: affected and tested versions, reproduction conditions
  and results, ruled-out alternatives, root cause, compatibility boundaries,
  and validation. Omit irrelevant detail, but not evidence needed to evaluate
  the claim.

## Git And Nix

Write commit messages in Conventional Commits format: `<type>: <summary>`.
When running `nix eval`, `nix flake check`, or `nix build`, invoke it
directly. Codex already sets `XDG_CACHE_HOME`; add an
`env XDG_CACHE_HOME=...` prefix only when debugging that variable.

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

For the default GitHub CI handoff, once remote CI is the only remaining step,
query status at most once, report the exact head and link plus remaining
acceptance, and return control. Pending is not passed. Do not watch, poll, or
schedule follow-up unless the user explicitly requested monitoring.

## Capability Routing

Use installed skills for reusable workflows; keep workflow details in
skill descriptions and `SKILL.md`, not in this global file.

For technical research, proactively seek relevant first-party X posts when
recent changes, conflicting evidence, or missing firsthand context could
materially affect the decision. Keep searches tied to a concrete question;
stop when it is answered or no useful leads emerge. Validate technical
conclusions against official docs, source, or reproducible evidence.

Treat GitHub and Context7 tokens as per-user secrets. Never route one
user's token or API key to another user's Codex configuration.

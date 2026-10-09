# AGENTS.md

Apply these defaults across repositories. Closer project instructions
override them.

## Working Style

- For one-off operator or repository-state incidents, recover the intended
  state and run existing focused checks.
- Use the smallest coherent change. Treat new tests, CI checks, policies,
  guardrails, abstractions, and documentation as separate scope unless the
  task requires them or concrete uncovered behavior warrants them.

## Communication

- On first use, briefly define uncommon names, terms, model variants, and
  project-specific concepts needed to understand the conclusion.
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

For an authorized operation that is safe to repeat and fails with a transient
network error, make at most three Codex-initiated retries after the first
attempt; continue when it succeeds. Honor explicit server wait requirements
and any lower retry limit set by the task or a skill. Count known earlier
Codex-initiated retries against the budget even when the command wrapper
changes; tool-internal retries are outside this budget.

For authentication failures, permission denials, deterministic configuration
errors, or remote writes with an uncertain result, diagnose or check the
result before retrying. When retries are exhausted, report the exact error,
attempt count, and blocked step, and continue independent work. A network
failure alone does not authorize changing repository URLs, transport, or
persistent configuration.

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

For technical research, proactively seek relevant first-party X posts when
recent changes, conflicting evidence, or missing firsthand context could
materially affect the decision. Keep searches tied to a concrete question;
stop when it is answered or no useful leads emerge. Validate technical
conclusions against official docs, source, or reproducible evidence.

Treat GitHub and Context7 tokens as per-user secrets. Never route one
user's token or API key to another user's Codex configuration.

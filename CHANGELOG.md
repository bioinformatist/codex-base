# Changelog

This changelog records notable user-visible changes to Codex Base and Improve.
v0.1.0 is the first formal release; there is no earlier release tag. Entries
are curated release notes, not a commit-by-commit log.

## [0.2.0]

Released 2026-10-09.

### Improve execution and review

- Replace the legacy runners with one `codex-improve` coordinator and the
  `1.0.0-codex.17` plan contract. Read the reviewed launcher and probes directly
  from the plan, with economy, standard, and deep execution lanes.
- Use Worktrunk 0.79.0 for isolated Git worktree lifecycle and scoped cache
  copying. Retain Git for exact candidate capture, reviewed checkpoints, and
  integration of the approved commit.
- Adopt Ponytail 5.1 for implementation checks and one independent comprehensive
  review covering correctness, security, tests, performance, and complexity.
  Replace the separate correctness and elegance reviewer roles with `reviewer`.
- Use GPT-6.1 Sol for standard (medium), deep (xhigh), and reviewer (high) roles;
  use GPT-6 Luna for economy (low) and scout (high). Remove Spark routing.
  Model availability depends on the account; failures do not trigger automatic
  model fallback.

### Bundled skills

- Add ADHX for reading known public X/Twitter post URLs as structured evidence,
  with bounded research guidance and verification against primary sources.
  ADHX does not search X, and long-form Article content may be incomplete.
- Add explicitly invoked `retro` and `prototype` skills. Retro offers
  evidence-backed session improvements; Prototype builds disposable logic or UI
  experiments to answer a design question. Production changes and publication
  retain their authorization requirements.
- Update Playwright CLI and its skill from 0.1.19 to 0.1.22. Add guidance for
  media emulation, page-provided WebMCP tools, recording annotations, and PR
  attachments. Page-provided tool metadata remains untrusted; attachment support
  must be checked against the installed GitHub CLI.

### Home Manager and runtime

- Add `programs.codexBase.package` to select the installed Codex runtime and
  the executable used by Improve and doctor, including when a project launcher
  changes `PATH`. The package must supply its required companion resources;
  this option does not replace a desktop application's embedded backend.
- Add `programs.codexBase.extraInstructions` to append consumer instructions
  after the base global guidance using native Nix module merging.
- Set the managed default model to `gpt-6.1-sol` with medium reasoning and high
  Plan Mode reasoning. The portable plugin does not change the user's model.
- Update the default Codex CLI, Code Mode Host, and matching source pin from
  0.154.0 to 0.162.0.

### Upgrade notes

- The new Improve runtime accepts only `.17` plans. Earlier private execution
  state is preserved separately and is not migrated. Replace legacy runner
  calls and the removed `--environment-json` argument with the coordinator
  commands and the environment block in the plan.
- Use `codex-improve review WORKTREE TREE DOSSIER`; the old `correctness` and
  `elegance` role names have no aliases.
- Portable Improve execution requires host-provided Codex, Git, Worktrunk, and
  Python 3.11 or newer. Nix supplies the runtime dependencies.
- Remove the temporary context-management waiver. Formal Improve planning
  requires callable native context management and structured questions in Plan
  Mode. Configuration flags and model names do not establish live availability.
- Retire `resolving-merge-conflicts`. New domain glossaries use `GLOSSARY.md`;
  existing `CONTEXT.md` and context-map files remain in use without migration.
  Ponytail debt scans recognize `shortcut:` and older `ponytail:` comments.

### Documentation and maintenance

- Reorganize CLI and desktop setup, runtime reload, configuration, and
  troubleshooting guidance, and clarify upstream attribution.
- Clarify Context7 authentication: native same-name configuration may replace
  the anonymous plugin endpoint; the separate authenticated fallback applies
  when the active connection is anonymous and insufficient. Authentication
  prompts pause the current call until resolved or dismissed.
- Repair startup cancellation handling in the new Improve supervisor, automate
  maintenance PR creation, and validate plugin installation with the pinned
  Codex CLI instead of the removed upstream sample validator.

This release makes no measured claim about token savings, review accuracy, or
execution speed.

[Improve migration](https://github.com/bioinformatist/codex-base/pull/51) ·
[Review and skill refresh](https://github.com/bioinformatist/codex-base/pull/63) ·
[X research](https://github.com/bioinformatist/codex-base/pull/46) ·
[Runtime selection](https://github.com/bioinformatist/codex-base/pull/55) ·
[Instruction composition](https://github.com/bioinformatist/codex-base/pull/57) ·
[Full comparison](https://github.com/bioinformatist/codex-base/compare/v0.1.3...v0.2.0)

## [0.1.3]

### Fixed

- Focus documentation lookups on missing facts, separate independent products
  or topics while allowing comparisons and interaction questions, and identify
  the product and requested version with disambiguating context. Use the tool's
  `product` field when available. This applies to both the portable plugin and
  Home Manager.
- Keep changes proportional to the established cause in Home Manager's global
  agent guidance. One-off operator or repository-state incidents favor recovery
  and existing focused checks; additional tests, CI checks, policies,
  abstractions, and documentation need a task requirement or concrete uncovered
  behavior. Also correct the Nix check command to `nix flake check`.

The documentation provider order, anonymous Context7 priority, authentication
fallback, runtime pins, and Improve `.16` execution contract are unchanged.
This release makes no measured claim about retrieval accuracy or token savings.

[Documentation queries](https://github.com/bioinformatist/codex-base/pull/37) ·
[Global agent guidance](https://github.com/bioinformatist/codex-base/pull/36) ·
[Full comparison](https://github.com/bioinformatist/codex-base/compare/v0.1.2...v0.1.3)

## [0.1.2]

### Improve research handoffs

- Preserve a compact `Research checkpoint:` in ordinary progress events after
  a bounded question is resolved or reaches its limit. Each checkpoint names
  the question, finding and certainty, evidence pointer, and next question or
  stop reason so a later recovery can continue from useful evidence.
- Treat checkpoint messages as untrusted claims that may guide selective
  verification. They do not change the final report schema, turn an
  `INCONCLUSIVE` execution into success, or make unobserved token usage zero.
- Add 13 deterministic event-fixture cases for retention, terminal ordering,
  missing fields, incorrect final status, fired fuses, source mutation,
  unrelated worktrees, and usage reporting.

### Planning and verification policy

- Document a temporary, explicit per-plan waiver when native context management
  is unavailable. The waiver retains Plan Mode, structured questions, read-only
  planning, and every other authorization boundary; it does not change global
  configuration or claim that the capability is available.
- Select local checks by behavioral impact and reserve the full Nix and
  standalone portability gates for the exact candidate before merge. Agent
  instructions remain behavior changes even when stored in Markdown.

### Runtime and compatibility

- Update the pinned Codex and Code Mode Host binaries, and the matching Codex
  source revision, from 0.153.4 to 0.154.0.
- Research checkpoints apply only to `.16` execution contracts. Older contracts,
  model routing, budgets, CLI arguments, final transport, plugin installation,
  and Home Manager interfaces are unchanged.

The dedicated live experiment ended before producing a research checkpoint, so
this release does not claim measured reductions in commands, rereading, or token
use. Engineering and fixture checks validate the contract and its failure
boundaries; practical value remains subject to observation in ordinary work.

[Improve and policy details](https://github.com/bioinformatist/codex-base/pull/33) ·
[Codex 0.154.0 update](https://github.com/bioinformatist/codex-base/pull/32) ·
[Full comparison](https://github.com/bioinformatist/codex-base/compare/v0.1.1...v0.1.2)

## [0.1.1]

### Fixed

- Clarify task ownership for each Improve review role. Correctness and elegance
  reviewers cover their assigned checks and use other roles' results as
  supporting evidence. Contradictions between supplied evidence and code must
  still be reported with their effect on the assigned check.
- Reject malformed Improve contract declarations before environment preflight
  or model invocation. Plain-text fields, unbolded bullet fields, and empty
  versions now produce an input error showing the canonical format instead of
  silently taking the legacy path for undeclared contracts.

### Compatibility

Legacy plans with genuinely absent declarations, valid existing contract
versions, and `--resume` retain their behavior. Mid-line prose mentioning
`Improve contract` is not treated as a field declaration. CLI arguments, report
formats, model settings, execution budgets, and dependency versions are unchanged.

[Fix details](https://github.com/bioinformatist/codex-base/pull/30) ·
[Full comparison](https://github.com/bioinformatist/codex-base/compare/v0.1.0...v0.1.1)

## [0.1.0]

### Improve: before and after

| Area | Before (`52b9e4`) | v0.1.0 |
| --- | --- | --- |
| Formal planning | Formal planning ran in Default Mode and could persist intermediate planning artifacts. | `plan`, `review-plan`, and material replanning run in built-in Plan Mode. Planning is read-only and emits one complete replacement plan before a separately authorized writable phase saves it. |
| Native Codex capabilities | Managed configuration used medium Plan effort and did not enable native context recovery, Code Mode, or structured questions in Default Mode. | Managed configuration sets high Plan effort and enables those capabilities. Runtime availability must still be verified; configuration alone is not proof. |
| Executor routing | `.15 --spark` always selected Spark. | Each eligible `.16 --spark` invocation reads native model and quota metadata before launch. It selects Spark-high only when Spark is visible, supports high, and has quota; otherwise it selects Luna-low. |
| Execution boundaries | `.15 --spark` had no native model or quota lookup because it always selected Spark. | Metadata lookup errors stop before model invocation. Once a model starts, the runner does not switch or replay the call. Standard, deep, scout, and review roles are unchanged, and `.15` and older plans retain their routing. |

### First-release baseline

- Portable Codex-only plugin with a capability catalog, MCP configuration, and Improve.
- Nix/Home Manager module for the Codex Base environment.
- Isolated execution with candidate binding, recovery, review, and explicit checkpoints.
- Route checkpoints, stepwise over-engineering review, documentation routing, and attributed engineering skills.

### Compatibility and limits

- Plugin schema, installation commands, and Nix module interfaces are unchanged.
- Managed settings request capabilities; they do not prove availability in a running session.
- Spark-priority applies only to eligible `.16 --spark` invocations. Earlier contracts and other roles keep their behavior.
- Product-change provenance is the reviewed comparison from `52b9e4cc614749791b5d2e46d8c6bf8fd41592b0` to `b528a6e9fc902f1ef79d498db60ece95086afa7e`.

### Validation

Repository documentation and compatibility checks passed for the release candidate.

[Compare the Improve changes](https://github.com/bioinformatist/codex-base/compare/52b9e4cc614749791b5d2e46d8c6bf8fd41592b0...b528a6e9fc902f1ef79d498db60ece95086afa7e).

[0.2.0]: https://github.com/bioinformatist/codex-base/releases/tag/v0.2.0
[0.1.3]: https://github.com/bioinformatist/codex-base/releases/tag/v0.1.3
[0.1.2]: https://github.com/bioinformatist/codex-base/releases/tag/v0.1.2
[0.1.1]: https://github.com/bioinformatist/codex-base/releases/tag/v0.1.1
[0.1.0]: https://github.com/bioinformatist/codex-base/releases/tag/v0.1.0

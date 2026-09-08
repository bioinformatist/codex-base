# Changelog

This changelog records notable user-visible changes to Codex Base and Improve.
v0.1.0 is the first formal release; there is no earlier release tag. Entries
are curated release notes, not a commit-by-commit log.

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

[0.1.0]: https://github.com/bioinformatist/codex-base/releases/tag/v0.1.0

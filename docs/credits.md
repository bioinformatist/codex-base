# Credits and licenses

Codex Base combines original integration work with incorporated upstream
projects. `vendor/sources.json` is the machine-readable source of truth for
revisions, included paths, and patch status; this page explains those records
without duplicating mutable pins.

| Source ID | Upstream | Included or adapted surface | License | Status in Codex Base |
|---|---|---|---|---|
| mattpocock-skills | [Matt Pocock's skills](https://github.com/mattpocock/skills) | Engineering and productivity skills including Grilling, Handoff, TDD, domain and module design, debugging, conflict resolution, questionnaires, and agent guidance | [MIT](../plugins/codex-base/licenses/mattpocock-skills-MIT.txt) | Adapted for Codex invocation, safety, and repository conventions |
| shadcn-improve | [shadcn Improve](https://github.com/shadcn/improve) | Audit playbook and plan-template foundations used by the Codex Base Improve workflow | [MIT](../plugins/codex-base/licenses/shadcn-improve-MIT.txt) | Adapted and substantially extended for durable planning, isolated execution, recovery, and review |
| stop-slop | [stop-slop](https://github.com/hardikpandya/stop-slop) | Prose-editing references used by the bundled stop-slop skill | [MIT](../plugins/codex-base/licenses/stop-slop-MIT.txt) | Adapted for Codex triggers and preservation rules |
| ponytail | [Ponytail](https://github.com/DietrichGebert/ponytail) | Ponytail Review, Audit, and Debt skills | [MIT](../plugins/codex-base/licenses/ponytail-MIT.txt) | Bundled without patching |
| playwright-cli | [Playwright CLI](https://github.com/microsoft/playwright-cli) | Headless-first Playwright skill; the full Nix surface also packages the CLI binary separately | [Apache-2.0](../plugins/codex-base/licenses/playwright-cli-Apache-2.0.txt) | Skill adapted for the Codex execution environment |

The repository itself is distributed under the [MIT License](../LICENSE). Each
bundled upstream license is retained with the portable plugin.

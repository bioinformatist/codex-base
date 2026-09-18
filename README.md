[简体中文](README.zh-CN.md)

<p align="center"><img src="plugins/codex-base/assets/codex-base.svg" alt="Codex Base branch and checkpoint logo" width="88"></p>

# Codex Base

Long coding tasks waste model usage when they repeatedly rebuild context, drift from settled intent, or rework over-engineered changes. Codex Base is designed to reduce that avoidable usage.

[![CI](https://github.com/bioinformatist/codex-base/actions/workflows/ci.yml/badge.svg)](https://github.com/bioinformatist/codex-base/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

![How direct editing and Codex Base handle a task as its context grows](docs/assets/codex-base-workflow.svg)

## How Codex Base addresses usage

| Usage concern | Mechanism |
|---|---|
| Main-model capacity | Qualifying, tightly bounded implementation uses Spark-priority under Improve `.16`: Spark when available with quota, otherwise Luna with low reasoning. Each new call checks again; a started model is never replayed on another model. [Codex-Spark has its own usage limits](https://learn.chatgpt.com/docs/agent-configuration/speed). |
| Avoidable work across the task | Formal planning captures settled decisions in one complete Plan Mode response; a later authorized writable phase can persist them. Documentation is checked before implementation, and every code-changing step is verified and simplified. This reduces repeated long-context reads, drift, over-engineering, and rework. |

Planning and review also use capacity. A small, clear edit is usually better handled directly, and Codex Base does not promise fewer tokens, lower cost, or less usage for every task.

Existing `.15` and older supported plans keep fixed Spark. Metadata query
errors stop before execution rather than selecting Luna. Luna usage is not
guaranteed or unlimited; the runner does not precheck its quota or switch
accounts or providers. Standard, deep, scout and review roles are unchanged.

## What Codex Base adds

[shadcn Improve](https://github.com/shadcn/improve) supplies the audit playbook and plan-template foundations. Codex Base adds:

- Formal planning produces a complete replacement plan in chat; a later authorized writable phase can persist the settled result.
- An isolated executor verifies and simplifies each changing step.
- Candidate-bound review and recovery, together with explicit checkpoints, keep work reviewable and resumable.

## Choose an installation

The columns below show what Codex Base provides or configures with each installation.

| Installation | Codex plugin | Nix / Home Manager full environment |
|---|---|---|
| Bundled engineering skills | Namespaced, such as `$codex-base:improve` | Unnamespaced, such as `$improve` |
| Improve runners | Bundled; Linux tools required | Packaged `codex-improve-*` commands |
| Global guidance and GitHub MCP | No | Yes |
| Mintlify / Context7 MCP servers and routing | Anonymous HTTP defaults and shared routing skill | Local anonymous Context7, optional authenticated Context7, and shared routing skill |
| Codex, Code Mode Host, Node, Playwright CLI | No | Pinned packages |

The [capability catalog](docs/capabilities.md) lists every trigger, responsibility, verification surface, and provenance. The plugin does not install Nix-only capabilities, commands, secrets, or global configuration.

The portable plugin configures anonymous Mintlify Index and Context7 HTTP endpoints plus one Mintlify-first routing skill. The Nix/Home Manager environment links the same skill while retaining local anonymous Context7 and optional per-user authenticated Context7. Both providers are public third parties: send only focused public lookup terms, never secrets, private code, full prompts, or non-public internal content. Native Codex configuration takes precedence over same-name plugin defaults.

The full Nix / Home Manager environment currently pins Codex 0.155.0 and Code Mode Host.

## Quick start

Plugins currently require a new Codex session after installation and are not available in the Codex IDE extension. Use the Codex CLI for this workflow.

- Linux users need Bash, GNU coreutils, Git, GNU sed, jq, and Codex on `PATH`.
- Windows users can use portable skills from a compatible Codex CLI environment. For the complete Improve runners and Nix/Home Manager environment, use WSL2 and keep the repository in the Linux filesystem, such as `~/src`, not `/mnt/c`.
- Native Windows Improve runners and Windows CI are not provided here.

```console
codex plugin marketplace add https://github.com/bioinformatist/codex-base
codex plugin add codex-base@bioinformatist-codex
```

### Verify the installation

```console
codex plugin list --marketplace bioinformatist-codex
codex mcp list --json
```

The output should show `codex-base@bioinformatist-codex` installed and enabled, with anonymous `mintlify_index` and `context7` MCP servers and no `context7_auth`. Then start a **new Codex session** and make a harmless functional check on disposable prose:

```text
Use $codex-base:stop-slop to tighten this disposable sentence without changing its facts.
```

<a id="temporary-context-waiver"></a>

### Temporary context-management waiver

> [!WARNING]
> **2026-09-12:** In [this announcement](https://x.com/thsottiaux/status/2098612714704891959), Tibo (@thsottiaux) reported disabling an opt-in context-management experiment that could cause early stops or replies to older messages. A [user-provided screenshot](docs/evidence/2026-09-12-tibo-context-management.png) is retained as a supporting archive.
>
> The announcement does not identify a configuration key or establish which accounts, subscriptions, or clients have access.

If formal Improve planning lacks native context management, check the session's live tools and preserve existing configuration. Do not edit local configuration, repeatedly toggle features, modify skills, or rebuild the environment to work around this unavailability.

To continue, the user must explicitly waive only the native context-management prerequisite for one named plan and its same-scope review. This is not an automatic or global waiver: Plan Mode, structured questions, read-only planning, and all other authorization boundaries remain required. For example:

```text
I approve waiving the native context-management prerequisite only for this plan and its same-scope review. Keep Plan Mode, structured questions, read-only planning, and all other authorization boundaries. Do not change configuration or global skills for this waiver.
```

A waiver neither restores the capability nor guarantees planning quality. Once the live capability is verified restored, new plans need no exception. Default Mode implementation, audits, and routine lifecycle bookkeeping are unaffected. The normal installation settings below are not a fix for this temporary unavailability.

### Native Codex configuration for non-Nix users

Home Manager already supplies these defaults. For other installations, merge this fragment once into your persistent Codex config (`CODEX_HOME/config.toml`, default `~/.codex/config.toml`):

```toml
plan_mode_reasoning_effort = "high"

[features]
context_management.experimental_mode = true
code_mode.enabled = true
default_mode_request_user_input = true
```

This is a merge fragment, not a replacement file or per-start flag. Keep unrelated configuration intact. `plan_mode_reasoning_effort` is top-level, while the three feature toggles belong in `[features]`. If any of these keys already exist, update them in place. Replace an existing boolean `context_management` or `code_mode` entry with the dotted form shown above; do not keep both a boolean and table form or duplicate a TOML key.

Start a new Codex session after saving the file. The fragment requests experimental context management, Code Mode, structured questions in Default Mode, and high reasoning effort in Plan Mode. Formal Improve planning still requires the session to expose native context management and structured questions: configured `true` values and a Plan Mode label do not prove that either capability is live. If one is missing, stop and reopen the task in a capable session unless the user explicitly grants the [temporary per-plan waiver](#temporary-context-waiver) for missing context management. That exception does not cover missing structured questions. `default_mode_request_user_input` does not automatically run Grilling or another question workflow.

The official [configuration reference](https://learn.chatgpt.com/docs/config-file/config-reference) covers experimental context management, Code Mode, and Plan Mode effort. The Default Mode question flag is instead checked against the pinned Codex 0.153.4 [feature declaration](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/features/src/lib.rs) and [request-user-input tests](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/core/tests/suite/request_user_input.rs). No wrapper or installer is required.

> [!NOTE]
> **Why these model defaults**
>
> - **Default Mode — `gpt-5.6-sol` with `medium` reasoning:** [GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) is OpenAI's flagship model for complex professional work, and `medium` is its default reasoning setting. This is a balanced baseline for routine implementation, audits, research, and maintenance: it retains flagship capability without imposing the latency and token use of higher reasoning on every turn.
> - **Plan Mode — `gpt-5.6-sol` with `high` reasoning:** formal planning must synthesize repository evidence, constraints, tradeoffs, and acceptance criteria before writable work begins. Reusing Sol keeps the model baseline consistent; raising only the reasoning effort gives this decision-heavy phase more room to deliberate. The extra latency and token use are accepted here to reduce downstream drift and rework, not because `high` is inherently better.
> - **When Plan Mode should use Astra:** [GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra) is OpenAI's most capable model for the hardest end-to-end work. Select it for a Plan Mode thread when planning must resolve high-impact, difficult-to-reverse product or architecture choices, integrate large or conflicting evidence across systems, or stay coherent through an unusually long and uncertain investigation. Do not switch merely because Plan Mode is active or a plan is lengthy; Sol/high remains the default for well-bounded planning.

> [!WARNING]
> `context_management.experimental_mode` is experimental, works only on the supported OpenAI backend, and requires an eligible ChatGPT Plus, Pro, or Pro Lite session; plan names alone do not guarantee eligibility.
> `code_mode.enabled` needs the matching Code Mode companion host.
> The Nix/Home Manager environment installs that host; a standalone CLI may not.
> Enabling these settings does not guarantee better results.

To roll back, preserve unrelated configuration, restore `plan_mode_reasoning_effort` to its previous value (`"medium"` is the managed Plan baseline), and explicitly set `context_management.experimental_mode`, `code_mode.enabled`, and `default_mode_request_user_input` to `false`. Do not only delete the keys: a merging overlay or source revert does not remove values already persisted in `config.toml`. Home Manager users must also reverse the managed overlay before activation, or activation will set the managed values again.

## First workflow

```text
Use $codex-base:improve plan <request>.
```

Codex namespace-qualifies plugin skills, so the portable plugin uses `$codex-base:improve`. The full Nix/Home Manager installation exposes `$improve plan <request>` without that prefix.

> [!NOTE]
> Enter built-in Plan Mode with `/plan` or Shift+Tab, then run `$improve plan ...` (or the portable plugin form `$codex-base:improve plan ...`). Improve first discovers available facts and asks only about material choices that remain unsettled. It renders the complete replacement plan in chat and writes no plan, questionnaire, handoff, or temporary file. Persist the plan only in a later authorized writable phase.

Default Mode implementation, audits, and ordinary lifecycle or dossier bookkeeping do not require a new formal-planning workflow. If formal planning is requested from Default Mode, switch to a capable Plan Mode session before continuing.

To install the full Nix/Home Manager environment, add the flake input and import the module:

```nix
{
  inputs.codex-base = {
    url = "github:bioinformatist/codex-base";
    inputs.nixpkgs.follows = "nixpkgs";
  };
  imports = [ inputs.codex-base.homeManagerModules.default ];
  programs.codexBase.enable = true;
}
```

## Learn and contribute

- [Detailed capability catalog](docs/capabilities.md)
- [Credits and upstream licenses](docs/credits.md)
- [Contributing](CONTRIBUTING.md)
- [Architecture](docs/architecture.md) and [updating](docs/updating.md)
- [Plugin versus Nix choice](#choose-an-installation)
- [Changelog](CHANGELOG.md)
- [MIT License](LICENSE)

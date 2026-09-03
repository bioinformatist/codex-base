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
| Main-model capacity | Qualifying, tightly bounded implementation can use the predefined Spark executor. [Codex-Spark is a separate model with its own usage limits](https://learn.chatgpt.com/docs/agent-configuration/speed); access and the plan's routing criteria still apply. |
| Avoidable work across the task | Decisions are written down early, documentation is checked before implementation, and every code-changing step is verified and simplified. This reduces repeated long-context reads, drift, over-engineering, and rework. |

Planning and review also use capacity. A small, clear edit is usually better handled directly, and Codex Base does not promise fewer tokens, lower cost, or less usage for every task.

## What Codex Base adds

[shadcn Improve](https://github.com/shadcn/improve) supplies the audit playbook and plan-template foundations. Codex Base adds:

- Settled decisions live in a persisted plan instead of only in chat.
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

The full Nix / Home Manager environment currently pins Codex 0.153.1 and Code Mode Host.

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

## First workflow

```text
Use $codex-base:improve plan <request>.
```

Codex namespace-qualifies plugin skills, so the portable plugin uses `$codex-base:improve`. The full Nix/Home Manager installation exposes `$improve plan <request>` without that prefix.

> [!NOTE]
> Run `$improve plan ...` (or the portable plugin form `$codex-base:improve plan ...`) in normal/default collaboration mode, not built-in Plan Mode. Plan Mode is read-only, so Improve cannot persist intermediate plans, semantic anchors, and review records there. Writing those decisions down lets later execution avoid reconstructing them from a long conversation.

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
- [MIT License](LICENSE)

[English](README.md)

<p align="center"><img src="plugins/codex-base/assets/codex-base.svg" alt="Codex Base 分支与检查点标志" width="88"></p>

# Codex Base

长任务经常把用量浪费在反复梳理上下文、偏离已经定下的目标，以及为过度设计返工上。Codex Base 要减少的正是这些不必要的消耗。

[![CI](https://github.com/bioinformatist/codex-base/actions/workflows/ci.yml/badge.svg)](https://github.com/bioinformatist/codex-base/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

![直接修改与 Codex Base 如何处理逐渐变长的任务](docs/assets/codex-base-workflow.zh-CN.svg)

## 用量省在哪里

| 用量问题 | Codex Base 的做法 |
|---|---|
| 主模型额度 | 边界和检查都已明确的实现任务，可以按计划交给预先指定的 Spark 执行器。[Codex-Spark 是独立模型，有自己的用量限制](https://learn.chatgpt.com/docs/agent-configuration/speed)；能否使用仍取决于访问权限和计划中的通道条件。 |
| 长任务中的重复消耗 | 尽早写下决定，实现前查证文档，每个改动步骤都先验证、再删繁就简，从而减少反复读取长上下文、做偏、过度设计和返工。 |

规划和审查也会消耗用量。小而明确的改动通常直接做更合适；Codex Base 不承诺每项任务都会减少 token、降低费用或减少总用量。

## Codex Base 增加了什么

[shadcn Improve](https://github.com/shadcn/improve) 提供了审计方法和计划模板。Codex Base 在此基础上增加：

- 把已经定下的决定写入持久化计划，而不是只留在对话里；
- 由隔离执行器验证并简化每个发生改动的步骤；
- 审查和恢复始终绑定对应的候选版本，再配合明确的检查点，让工作可审查、可续接。

## 选择安装方式

下表只说明 Codex Base 在两种安装方式中会提供或配置什么。

| 安装方式 | Codex 插件 | Nix / Home Manager 完整环境 |
|---|---|---|
| 内置工程技能 | 带命名空间，例如 `$codex-base:improve` | 无命名空间，例如 `$improve` |
| Improve 执行器 | 随技能打包；需要 Linux 工具 | 打包为 `codex-improve-*` 命令 |
| 全局指引与 GitHub MCP | 无 | 有 |
| Mintlify / Context7 MCP 服务及路由策略 | 匿名 HTTP 默认配置及共享路由技能 | 本地匿名 Context7、可选的认证 Context7 及共享路由技能 |
| Codex、Code Mode Host、Node、Playwright CLI | 不安装 | 固定版本的软件包 |

[详细能力目录](docs/capabilities.zh-CN.md)列出了每项能力的触发条件、职责、验证方式与来源。Codex 插件不会安装仅属于 Nix / Home Manager 完整环境的能力、命令、密钥或全局配置。

可移植插件会配置匿名的 Mintlify Index 与 Context7 HTTP 端点，并提供一份先查 Mintlify 的共享路由技能。Nix / Home Manager 环境会链接同一技能，同时保留本地匿名 Context7 及可选的用户级认证 Context7。两家服务都是公开的第三方服务：只发送聚焦的公开检索词，绝不能发送密钥、私有代码、完整提示词或非公开内部内容。Codex 原生配置中的同名项优先于插件默认值。

Nix / Home Manager 完整环境当前固定 Codex 0.153.2 和 Code Mode Host。

## 快速开始

目前安装插件后需要新建 Codex 会话，且 Codex IDE 扩展尚不支持插件。请用 Codex CLI 运行这套工作流。

- Linux 用户需要 `PATH` 中已有 Bash、GNU coreutils、Git、GNU sed、jq 和 Codex。
- Windows 用户可在兼容的 Codex CLI 环境使用可移植技能。若要运行完整 Improve 执行器及 Nix / Home Manager 完整环境，请使用 WSL2，并把仓库放在 Linux 文件系统中（例如 `~/src`），不要放在 `/mnt/c` 下。
- 本仓库不提供原生 Windows Improve 执行器或 Windows CI。

```console
codex plugin marketplace add https://github.com/bioinformatist/codex-base
codex plugin add codex-base@bioinformatist-codex
```

### 验证安装

```console
codex plugin list --marketplace bioinformatist-codex
codex mcp list --json
```

输出应显示 `codex-base@bioinformatist-codex` 已安装且已启用，并列出匿名的 `mintlify_index` 和 `context7` MCP 服务，但不应有 `context7_auth`。然后新建一个 **Codex 会话**，对可丢弃文字做一次无副作用的功能验证：

```text
使用 $codex-base:stop-slop 精简下面这句临时文本，不要改变其中的事实。
```

## 首次工作流

```text
使用 $codex-base:improve plan <request>。
```

Codex 会用插件命名空间限定技能名称，因此可移植插件使用 `$codex-base:improve`。Nix / Home Manager 完整环境不带这个前缀，使用 `$improve plan <request>`。

> [!NOTE]
> 请在普通/默认协作模式中运行 `$improve plan ...`（Codex 插件写法为 `$codex-base:improve plan ...`），不要使用内置 Plan Mode。Plan Mode 是只读的，Improve 无法在其中写入中间计划、语义锚点和审查记录。把这些决定写下来，后续执行才不必从很长的对话中重新梳理。

如需安装 Nix / Home Manager 完整环境，请添加 flake 输入并导入模块：

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

## 了解更多与参与贡献

- [详细能力目录](docs/capabilities.zh-CN.md)
- [上游致谢与许可证](docs/credits.md)
- [贡献指南](CONTRIBUTING.md)
- [架构](docs/architecture.md)与[更新说明](docs/updating.md)
- [Codex 插件与 Nix / Home Manager 的选择](#选择安装方式)
- [MIT 许可证](LICENSE)

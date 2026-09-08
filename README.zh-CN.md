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
| 主模型额度 | 符合通道条件、边界明确的实现任务，在 Improve `.16` 下使用 Spark 优先策略：Spark 可用且有额度时选 Spark，否则选低推理强度的 Luna。每次新调用重新检查；模型启动后不会换模重放。[Codex-Spark 有独立的用量限制](https://learn.chatgpt.com/docs/agent-configuration/speed)。 |
| 长任务中的重复消耗 | 正式规划先在 Plan Mode 的一份完整回复中记录已经定下的决定，之后获准进入可写阶段时再持久化。实现前查证文档，每个改动步骤都先验证、再删繁就简，从而减少反复读取长上下文、做偏、过度设计和返工。 |

规划和审查也会消耗用量。小而明确的改动通常直接做更合适；Codex Base 不承诺每项任务都会减少 token、降低费用或减少总用量。

已有的 `.15` 及更早受支持计划仍使用固定 Spark。元数据查询出错会在执行前停止，
不会因此改选 Luna。Luna 并非保证可用或不限量；执行器不预查它的额度，也不切换
账号或提供商。standard、deep、scout 和审查角色保持不变。

## Codex Base 增加了什么

[shadcn Improve](https://github.com/shadcn/improve) 提供了审计方法和计划模板。Codex Base 在此基础上增加：

- 正式规划先在对话中给出完整的替换计划；之后获准进入可写阶段时，再持久化已经定下的结果；
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

Nix / Home Manager 完整环境当前固定 Codex 0.153.4 和 Code Mode Host。

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

### 面向非 Nix 用户的 Codex 原生配置

Home Manager 已经提供了这些默认值。其他安装方式只需将以下片段合并到持久配置文件中一次（`CODEX_HOME/config.toml`，默认 `~/.codex/config.toml`）：

```toml
plan_mode_reasoning_effort = "high"

[features]
context_management.experimental_mode = true
code_mode.enabled = true
default_mode_request_user_input = true
```

这是合并片段，不应替换整个文件，也不是每次启动要带的参数；请保留其他无关配置。`plan_mode_reasoning_effort` 是顶层键，三个功能开关则属于 `[features]`。如果其中某个键已经存在，请直接修改原定义。若 `context_management` 或 `code_mode` 目前是布尔值，请用上面的点分形式替换它；不要同时保留布尔值和表，也不要重复定义同一个 TOML 键。

保存后，请新建 Codex 会话。这个片段会请求实验性上下文管理、Code Mode、Default Mode 中的结构化提问，以及 Plan Mode 中的高推理强度。正式 Improve 规划仍要求当前会话实际提供原生上下文管理和结构化提问；配置值为 `true` 或界面显示 Plan Mode，都不能证明能力已经可用。如果缺少任何一项，请停止并换到具备这些能力的会话。`default_mode_request_user_input` 不会自动运行 Grilling 或其他提问工作流。

官方[配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)说明了实验性上下文管理、Code Mode 和 Plan Mode 推理强度。Default Mode 提问开关则由当前固定的 Codex 0.153.4 [功能声明](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/features/src/lib.rs)及[结构化提问测试](https://github.com/openai/codex/blob/3d2ee51ca2d5db578f328aa75e20aa22c0197c9a/codex-rs/core/tests/suite/request_user_input.rs)验证。无需启动脚本或安装器。

> [!NOTE]
> **为什么采用这组模型默认值**
>
> - **Default Mode — `gpt-5.6-sol`、`medium` 推理强度：**[GPT-5.6 Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) 是 OpenAI 面向复杂专业工作的旗舰模型，`medium` 也是它的默认推理设置。这为日常实现、审计、研究和维护提供了均衡基线：保留旗舰模型能力，同时避免让每一轮都承担更高推理强度带来的额外延迟和 token 消耗。
> - **Plan Mode — `gpt-5.6-sol`、`high` 推理强度：**正式规划要在进入可写阶段前综合仓库证据、约束、取舍和验收条件。继续使用 Sol 可以保持模型基线一致；只提高推理强度，则为这个决策密集的阶段增加思考深度。这里接受额外的延迟和 token 消耗，是为了减少后续做偏与返工，而不是因为 `high` 天然更好。
> - **Plan Mode 何时应使用 Astra：**[GPT-6 Astra](https://developers.openai.com/api/docs/models/gpt-6-astra) 是 OpenAI 能力最强的模型，适合最困难的端到端工作。当规划必须解决影响重大且难以回退的产品或架构选择、综合多个系统中的大量或相互冲突的证据，或在异常漫长且不确定的调查中保持连贯时，才应为该 Plan Mode 会话选择 Astra。不要仅仅因为进入了 Plan Mode 或计划篇幅较长就切换模型；对于边界清楚的规划，默认仍是 Sol/high。

> [!WARNING]
> `context_management.experimental_mode` 是实验特性，仅适用于受支持的 OpenAI 后端，并且需要符合资格的 ChatGPT Plus、Pro 或 Pro Lite 会话；仅凭套餐名称不能保证具备资格。
> `code_mode.enabled` 依赖匹配的 Code Mode companion host。
> Nix/Home Manager 环境会安装该 companion，单独 CLI 不一定具备。
> 启用这些设置也不保证结果更好。

如需回退，请保留其他无关配置，将 `plan_mode_reasoning_effort` 恢复为先前的值（托管的 Plan 基线为 `"medium"`），并明确把 `context_management.experimental_mode`、`code_mode.enabled` 和 `default_mode_request_user_input` 设为 `false`。不要只删除这些键：合并式覆盖层或源码回退不会清除已经写入 `config.toml` 的值。Home Manager 用户还必须在下次激活前撤销托管覆盖层中的这些设置，否则激活时会再次写入托管值。

## 首次工作流

```text
使用 $codex-base:improve plan <request>。
```

Codex 会用插件命名空间限定技能名称，因此可移植插件使用 `$codex-base:improve`。Nix / Home Manager 完整环境不带这个前缀，使用 `$improve plan <request>`。

> [!NOTE]
> 请先用 `/plan` 或 Shift+Tab 进入内置 Plan Mode，再运行 `$improve plan ...`（Codex 插件写法为 `$codex-base:improve plan ...`）。Improve 会先查清已有事实，只询问仍未确定且会实质影响任务的选择，然后在对话中给出完整的替换计划；此时不会写入计划、问卷、交接或临时文件。只有之后获准进入可写阶段，才持久化计划。

Default Mode 中的实现、审计及普通生命周期或 dossier 记录不需要重新走正式规划流程。如果在 Default Mode 中要求正式规划，请先切换到具备所需能力的 Plan Mode 会话。

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
- [版本记录（英文）](CHANGELOG.md)
- [MIT 许可证](LICENSE)

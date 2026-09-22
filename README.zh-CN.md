[English](README.md)

<p align="center"><img src="plugins/codex-base/assets/codex-base.svg" alt="Codex Base 分支与检查点标志" width="88"></p>

# Codex Base

Codex Base 将社区技能移植、适配到 Codex，并结合团队实践补充工作流与环境集成。它希望减少长任务中反复梳理上下文、偏离既定决策和过度设计造成的返工。

> [!WARNING]
> 这是我把团队正在使用的 agent harness（围绕 Codex 组织的指令、工具和工作流基座）公开分享出来的工程，不是面向绝大多数用户的产品。AI 和 Codex 演进很快，本仓库会长期处于 `unstable` 状态，使用者可能还需要完成不少额外配置。
>
> 公开它，是为了分享工程实践，邀请大家共同完善这套基座。我们相信，共同投入能帮助各自的团队更快地用好技术进展、改善生产力，做出更先进的产品。我们热烈欢迎有价值的 issue 和 PR，也希望参与者认真理解项目的意图，尊重文档中的约定。

[![CI](https://github.com/bioinformatist/codex-base/actions/workflows/ci.yml/badge.svg)](https://github.com/bioinformatist/codex-base/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

[快速开始](#快速开始) · [首次工作流](#首次工作流) · [更新](#更新后重新加载) · [配置参考](docs/configuration.zh-CN.md)

## 我们做了什么

我们的 Improve 工作流以 [shadcn Improve](https://github.com/shadcn/improve) 的审计与规划方法为基础，并选取、适配了 [Matt Pocock 的 skills](https://github.com/mattpocock/skills)，用于需求澄清、调试、测试、设计和 agent 指导。我们还适配并整合了用于过度设计审查、全库审计和技术债梳理的 [Ponytail](https://github.com/DietrichGebert/ponytail)、用于文字编辑的 [stop-slop](https://github.com/hardikpandya/stop-slop)，以及用于浏览器操作的 [Playwright CLI skill](https://github.com/microsoft/playwright-cli)。

我们的工作侧重于将这些基础适配到 Codex，扩展并衔接规划、执行和审查流程，补充文档检索路由，以及维护插件和 Nix/Home Manager 环境。在这套集成中：

- 正式规划先解决重要选择，在对话中给出完整计划；之后获准的实现阶段可以持久化计划，并委派边界明确的工作。
- 实现前查证当前文档，隔离执行器验证并简化每个改动步骤；审查和检查点明确对应的候选版本，让工作可以续接和评估。
- 共享技能覆盖文档检索、调试、测试、设计和文字审阅。[详细能力目录](docs/capabilities.zh-CN.md)列出了它们的触发方式和安装要求。

[致谢与许可证](docs/credits.md)说明了上游贡献与我们的适配内容；[来源记录](vendor/sources.json)列出了纳入的路径和固定版本。

![直接修改与 Codex Base 如何处理逐渐变长的任务](docs/assets/codex-base-workflow.zh-CN.svg)

对于适合轻量执行、边界明确的实现任务，我们优先使用可用且有额度的 Spark，否则使用低推理强度的 Luna。[Codex-Spark 有独立的用量限制](https://learn.chatgpt.com/docs/agent-configuration/speed)；兼容性和失败处理见[执行器路由](docs/architecture.md#executor-routing)。

规划和审查也会消耗用量，小而明确的修改通常直接做更合适；Codex Base 不承诺每项任务都能减少 token 或降低费用。

## 快速开始

> [!NOTE]
> 如果安装配置让你犯难，又想体验与我（本仓库 owner）近似的 Nix / Home Manager 完整环境，不妨把这份 README 交给 Codex，请它帮你配置（笑）。

### 1. 确认执行主机

可以使用 Codex CLI，或 ChatGPT 桌面应用中的 Codex；IDE 扩展尚不支持插件。本仓库支持 Codex 工作流，不支持普通 Chat 或 Work 对话。参见官方[插件说明](https://learn.chatgpt.com/docs/plugins)。

请在实际执行任务的机器上安装和配置 Codex Base：

| 客户端 | 执行主机与 Codex 运行时 |
|---|---|
| Codex CLI | 运行 `codex` 的机器，使用 `PATH` 中的 CLI 安装。 |
| 本地桌面对话 | 桌面所在机器，使用应用内置的 Codex 运行时，其版本可能与系统 CLI 不同。 |
| 桌面通过 SSH 连接 | 所选远端主机，桌面客户端在此启动 Codex App Server；远端登录 shell 必须能从 `PATH` 找到 `codex`。 |

SSH 连接请按官方[连接说明](https://learn.chatgpt.com/docs/remote-connections#connect-to-an-ssh-host)配置。只在桌面客户端上安装，不会配置远端主机。

Linux 执行环境需要 `PATH` 中已有 Bash、GNU coreutils、Git、GNU sed、jq 和 Codex。Windows 用户可以在兼容的 Codex CLI 环境中使用可移植技能；完整 Improve 执行器和 Nix/Home Manager 环境需要 Linux，例如 WSL2。WSL 仓库应放在其 Linux 文件系统内（例如 `~/src`，不要放在 `/mnt/c`）。本仓库不提供原生 Windows Improve 执行器或 Windows CI。

<a id="选择安装方式"></a>

### 2. 选择安装方式

已有 Codex 环境、只想加入可移植工作流时，选择插件；希望托管完整 Linux 环境时，选择 Home Manager。

| 提供或配置的内容 | Codex 插件 | Nix / Home Manager 完整环境 |
|---|---|---|
| 工程技能 | 带命名空间，例如 `$codex-base:improve` | 无命名空间，例如 `$improve` |
| Improve 执行器 | 随技能打包，需要 Linux 工具 | 打包为 `codex-improve-*` 命令 |
| 全局指引与 GitHub MCP | 无 | 有 |
| Mintlify / Context7 文档服务 | 匿名 HTTP 默认配置 | HTTP Mintlify、本地匿名 Context7 和可选的用户级认证 |
| Codex、Code Mode Host、Node、Playwright CLI | 不安装 | 固定版本的软件包 |

#### Codex 插件

在执行主机上运行：

```console
codex plugin marketplace add https://github.com/bioinformatist/codex-base
codex plugin add codex-base@bioinformatist-codex
codex plugin list --marketplace bioinformatist-codex
```

输出应显示 `codex-base@bioinformatist-codex` 已安装且已启用。插件不会安装 Codex、主机软件包或全局配置。

#### Nix / Home Manager

向已有的 `flake.nix` 添加输入：

```nix
inputs.codex-base = {
  url = "github:bioinformatist/codex-base";
  inputs.nixpkgs.follows = "nixpkgs";
};
```

然后在能够访问 `inputs` 的 Home Manager 模块中添加：

```nix
{
  imports = [ inputs.codex-base.homeManagerModules.default ];
  programs.codexBase.enable = true;
}
```

按你平时的部署流程激活使用该模块的 Home Manager 或 NixOS 配置。这条路径会提供技能、执行器和托管配置，无需再单独安装插件。

Nix / Home Manager 完整环境当前固定 Codex 0.155.1 和 Code Mode Host。

### 3. 配置并验证

Home Manager 已提供运行时默认配置。仅安装插件时，请按 [Codex 原生配置](docs/configuration.zh-CN.md#native-codex-configuration)启用规划所需能力，并在具备 companion host 时配置 Code Mode。随后按[更新后重新加载](#更新后重新加载)操作。

两种安装方式都提供 Mintlify 和 Context7，用于查询公开文档。插件使用匿名的 Mintlify Index 与 Context7 HTTP 端点；Home Manager 使用 HTTP Mintlify 和本地 Context7。可以先使用这些匿名默认配置；可选的用户级认证及验证方式见 [Context7 认证](docs/configuration.zh-CN.md#context7-authentication)。Codex 原生配置中的同名项优先于插件默认值。只向这两家第三方服务发送聚焦的公开检索词，绝不能发送密钥、私有代码、完整提示词或非公开内部内容。

在执行主机上检查已注册的服务：

```console
codex mcp list --json
```

没有原生覆盖配置、仅安装插件的环境应列出 `mintlify_index` 和 `context7`，不应有 `context7_auth`。服务已注册不代表服务或凭据已经可用。

新建 Codex 任务，试一次无副作用的技能调用：

```text
使用 $codex-base:stop-slop 精简这句话，不要改变事实：“在目前这个时间点，测试套件中包含三个测试。”
```

Home Manager 用户请使用不带插件前缀的 `$stop-slop`。这一步检查技能是否能被发现；正式规划还需要满足下文的要求。

## 首次工作流

本节适用于**两种安装方式**。一个 Codex 任务就是一条对话：在 CLI 中是一段对话，在桌面端则是侧边栏某个项目下的一条 Codex 对话。在其中进入 Plan Mode 或调用 `$improve`，都不会创建另一个任务。

### 以合适的模型启动任务

托管默认值是 `gpt-5.6-sol`、`medium` 推理强度，进入 Plan Mode 后提高为 `high`，适用于日常工作。正式 Improve 规划还要求原生 Context Manager（通过笔记和检索跨上下文窗口延续任务历史的功能）及结构化提问能力。上下文管理资格在任务启动时判定，因此应先启用实验，再从 **`gpt-6-astra`** 启动这类任务。这只是必要条件，并不保证能力可用：服务端 rollout、登录方式、账户资格和客户端支持仍会参与判定。详见官方[模型文档](https://learn.chatgpt.com/docs/models#experimental-context-management)。

| 客户端 | 如何启动 Astra 任务 |
|---|---|
| CLI，包括 Home Manager 安装 | 在仓库目录中运行 `codex -m gpt-6-astra`。 |
| 本地桌面或桌面通过 SSH 连接 | 新建 Codex 对话，在发送首条请求之前选好 Astra 作为启动模型。如果运行时或配置有变，先重新加载对应后端。 |

把已有 Sol 对话切成 Astra，不会重新执行任务初始化。CLI 的 `/new` 采用有效默认配置及显式启动设置，可能与当前对话的模型不同；`/model` 也可能保存新的默认值。用 `codex -m gpt-6-astra` 启动，可以明确选择 Astra，并让同次运行中的后续 `/new` 继承它。已核对的 0.155.1 行为见[模型选择与 CLI 作用域](docs/configuration.zh-CN.md#model-choice)。

<a id="temporary-context-waiver"></a>

正式规划前应核对会话实际提供的工具：配置值为 `true` 或界面显示 Plan Mode，都不能证明能力已经可用；以 Astra 启动任务同样不能证明原生上下文管理已经可用。缺少该能力时，不要反复重启、重建或切换同一配置；应改用服务端实际开放该能力的会话，或请用户明确授予[单计划临时豁免](docs/configuration.zh-CN.md#temporary-context-waiver)。结构化提问和其他规划要求仍须满足。

### 先规划，再授权实现

请先用 `/plan` 或 Shift+Tab 进入内置 Plan Mode（CLI）；桌面对话输入框也支持 [`/plan`](https://learn.chatgpt.com/docs/reference/slash-commands)。然后按安装方式调用 Improve：

| 安装方式 | 提示词 |
|---|---|
| 插件 | `$codex-base:improve plan <request>` |
| Home Manager | `$improve plan <request>` |

Improve 会查清事实、询问重要且尚未确定的选择，然后在对话中给出完整的替换计划。规划阶段不会创建计划、问卷、交接或临时文件。接受计划后，再在 Default Mode 中授权实现；后续可写阶段可以持久化计划并执行。

Default Mode 中的实现、审计和普通生命周期记录不需要重新走正式规划流程。不需要正式规划的任务可以直接使用相应技能，见[详细能力目录](docs/capabilities.zh-CN.md)。

## 更新后重新加载

先[更新已安装的插件或激活使用该模块的 Nix 配置](docs/updating.md#applying-an-update)；仅重启不会获取新文件。等相关任务执行完毕后，重新加载实际执行任务的运行时：

| 客户端 | 重新加载方式 |
|---|---|
| CLI | 退出并重新启动 Codex。 |
| 本地桌面 | 完全退出并重新打开 ChatGPT 桌面应用，再新建 Codex 对话。只关闭窗口不等于退出应用。需要时单独更新应用，因为它[内置的 Codex 可能与系统 CLI 不同](https://learn.chatgpt.com/docs/reference/troubleshooting#feature-is-working-in-the-codex-cli-but-not-in-the-chatgpt-desktop-app)。 |
| 桌面通过 SSH 连接 | 更新远端安装后，按官方[连接说明](https://learn.chatgpt.com/docs/remote-connections#connect-to-an-ssh-host)，在**设置 → Connections（连接）→ SSH** 中重启对应主机的后端，然后新建对话。 |

SSH 场景应核对正在运行的远端 Codex App Server；`codex --version` 只显示新调用程序的版本。重启桌面客户端或新建对话，都不能证明远端进程已重启。继续旧对话会保留原有历史。

## 了解更多与参与贡献

- [配置、认证与排障](docs/configuration.zh-CN.md)
- [详细能力目录](docs/capabilities.zh-CN.md)
- [贡献指南](CONTRIBUTING.md)、[架构](docs/architecture.md)与[更新说明](docs/updating.md)
- [上游致谢与许可证](docs/credits.md)
- [版本记录（英文）](CHANGELOG.md)
- [MIT 许可证](LICENSE)

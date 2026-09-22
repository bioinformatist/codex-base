[English](configuration.md) · [返回快速开始](../README.zh-CN.md#快速开始)

# 配置与排障

本页供查阅运行时设置、可选的文档服务凭据和规划能力排障。安装步骤以及 CLI、桌面端共用的工作流见 [README](../README.zh-CN.md#首次工作流)。

- [Codex 原生配置](#native-codex-configuration)
- [模型选择](#model-choice)
- [Context7 认证](#context7-authentication)
- [原生上下文管理临时豁免](#temporary-context-waiver)
- [回退运行时设置](#reverting-runtime-settings)

<a id="native-codex-configuration"></a>

## Codex 原生配置

Home Manager 已提供这些运行时默认值。其他安装方式需将以下片段合并到执行主机的持久 Codex 配置中一次（`CODEX_HOME/config.toml`，默认 `~/.codex/config.toml`）：

```toml
plan_mode_reasoning_effort = "high"

[features]
context_management.experimental_mode = true
code_mode.enabled = true
default_mode_request_user_input = true
```

| 配置项 | 用途与依赖 |
|---|---|
| `plan_mode_reasoning_effort` | 提高 Plan Mode 的推理强度，不改变模型。 |
| `context_management.experimental_mode` | 请求启用实验性原生上下文管理；它不能覆盖服务端 rollout，也不能覆盖服务端为当前账户和模型下发的能力状态。认证方式、启动模型、客户端及当前会话也必须符合资格。请按共用的[任务启动说明](../README.zh-CN.md#首次工作流)操作。 |
| `code_mode.enabled` | 请求启用 Code Mode，需要匹配的 Code Mode companion host。Home Manager 会安装它，独立 CLI 不一定具备；缺少 host 时应设为 `false`。 |
| `default_mode_request_user_input` | 让 Default Mode 可以使用结构化提问，不会自动调用 Grilling 或其他提问工作流。 |

这是合并片段，不应替换整个文件，也不是每次启动要带的参数。请保留无关配置。`plan_mode_reasoning_effort` 是顶层键，三个功能开关属于 `[features]`。已有键应就地修改；若 `context_management` 或 `code_mode` 目前为布尔值，请用上面的点分形式替换，不要同时保留布尔值和表，也不要重复定义 TOML 键。

保存后[重新加载执行运行时](../README.zh-CN.md#更新后重新加载)。配置开关只是请求能力，不能证明当前任务已经具备它们，也不保证结果更好。实验需要受支持的 OpenAI 后端及符合资格的 ChatGPT 会话，服务端仍可不向启动模型开放该能力。当前开放范围请查阅[模型文档](https://learn.chatgpt.com/docs/models#experimental-context-management)。正式规划缺少原生上下文管理时，应使用[单计划临时豁免](#temporary-context-waiver)流程，而非反复改配置。

官方[配置参考](https://learn.chatgpt.com/docs/config-file/config-reference)说明了上下文管理、Code Mode 和 Plan Mode 推理强度。Default Mode 提问开关则由已核对的 Codex [功能声明](https://github.com/openai/codex/blob/f0a1b8f0849d90960bc406b848f32e5a129b0457/codex-rs/features/src/lib.rs)及[结构化提问测试](https://github.com/openai/codex/blob/f0a1b8f0849d90960bc406b848f32e5a129b0457/codex-rs/core/tests/suite/request_user_input.rs)支持。

<a id="model-choice"></a>

## 模型选择

这些选择与安装方式无关。Home Manager 会托管 Sol 默认值；只安装插件不会改动用户的模型配置。

| 工作 | 模型与推理强度 | 理由 |
|---|---|---|
| 日常实现、审计、调研和维护 | `gpt-5.6-sol`、`medium` | 平衡能力、延迟和 token 消耗。 |
| 不要求原生上下文管理的有界规划 | `gpt-5.6-sol`、`high` | 保持模型不变，为约束和取舍留出更多推理空间；正式 Improve 规划仍须满足前置条件，或取得明确豁免。 |
| 使用原生上下文管理的正式 Improve 规划 | 服务端已开放该实验时，以 `gpt-6-astra` 新建任务，再进入 Plan Mode | 资格检查依赖启动模型，因此必须新建 Astra 任务；但这不能覆盖服务端关闭的能力。 |
| 困难的产品或架构选择、冲突证据或异常漫长的调查 | `gpt-6-astra` | 即使不考虑上下文管理要求，更强的推理能力也可能值得额外成本。 |

参见官方 [Sol](https://developers.openai.com/api/docs/models/gpt-5.6-sol) 和 [Astra](https://developers.openai.com/api/docs/models/gpt-6-astra) 模型说明。每项规划并非都需要更高推理强度或更强的模型。

CLI 和桌面启动步骤见 [README](../README.zh-CN.md#首次工作流)。CLI 用户若保留 Sol 默认值，`codex -m gpt-6-astra` 是最简单的一次性选择；也可以将 Astra 设为持久默认值，或在启动时选择自行配置的 Astra profile，Codex Base 不提供此 profile。命令用法见官方 [CLI 参考](https://learn.chatgpt.com/docs/developer-commands?surface=cli)。

在锁定的 Codex 0.155.1 实现中，需要区分设置的作用域：

- 普通 `/model` 选择会更新当前对话，并尝试保存模型和推理强度默认值。Plan Mode 推理范围提示中的“仅用于 Plan Mode”则只保存 Plan 推理覆盖值，不保存模型默认值。参见[选择处理逻辑](https://github.com/openai/codex/blob/be2951ea34f0d295ed0becf97079f92fa5f6950e/codex-rs/tui/src/chatwidget/model_popups.rs)。
- `/new` 读取服务端的有效默认配置，同时保留显式启动模型和 profile 设置，不会直接复制上一条对话的模型。参见[新会话配置](https://github.com/openai/codex/blob/be2951ea34f0d295ed0becf97079f92fa5f6950e/codex-rs/tui/src/app/new_session.rs)及其[测试](https://github.com/openai/codex/blob/be2951ea34f0d295ed0becf97079f92fa5f6950e/codex-rs/tui/src/app/tests/new_session_tests.rs)。
- 因此，`/model` → Astra → `/new` 可以在新默认值保存并生效后使用 Astra；如果有效默认值或启动覆盖值仍是 Sol，也可能继续使用 Sol。判断某个环境时，应检查 `/status`、`/debug-config` 和配置保存警告。

上下文管理另有[初始化检查](https://github.com/openai/codex/blob/be2951ea34f0d295ed0becf97079f92fa5f6950e/codex-rs/core/src/session/token_budget.rs)。Codex 0.155.1 同时要求本地选择加入、启动模型的服务端元数据包含 `supports_experimental_context = true`、受支持的 OpenAI 后端以及符合资格的 ChatGPT 认证。新建 Astra 任务只满足启动模型的时机要求；如果服务端把该登录身份下的模型标记为不支持，本地配置无法强制激活。

<a id="context7-authentication"></a>

## Context7 认证

Mintlify 和 Context7 通过 MCP（Codex 连接外部工具的协议）提供公开文档。两种安装方式共用相同的路由技能：先查 Mintlify，必要时使用 Context7，匿名结果不足时再用认证 Context7 fallback，最后回退到官方一手资料。原生配置可以覆盖插件的同名端点。查询只能包含聚焦的公开检索词，不能包含密钥或私有内容。

匿名 Context7 无需账户。认证属于可选的用户级配置，Codex Base 不会内置共享密钥。

### 仅安装插件

如需保留匿名优先顺序，另加一个 OAuth fallback：

```console
codex mcp add context7_auth --url https://mcp.context7.com/mcp/oauth
codex mcp login context7_auth
```

这不会改变插件的 `context7` 端点。Context7 官方的 [`npx ctx7 setup --codex`](https://context7.com/docs/clients/codex) 会用同名 `context7` 创建原生认证配置，且可能补充智能体指引。这会覆盖插件默认值；只有希望将认证 Context7 作为主连接而非 fallback 时，才应使用该命令。

### Nix / Home Manager

让模块指向运行时密钥文件：

```nix
programs.codexBase.context7ApiKeyFile = /run/secrets/context7-api-key;
```

明文密钥不能写入 Nix 源码或 Nix store，应由 SOPS、agenix 等密钥管理器提供该文件。Home Manager 会保留匿名 `context7` 并添加 `context7_auth`；后者的包装器会读取文件，把 `CONTEXT7_API_KEY` 传给本地 MCP 服务。

### 验证认证

完成任一配置后，[重新加载运行时](../README.zh-CN.md#更新后重新加载)，再运行 `codex mcp list --json`。服务已注册不能证明凭据可用；一次性诊断时，可以要求 Codex 用 `context7_auth` 查询一项聚焦的公开文档。Nix stdio 适配器显示 `auth_status: "unsupported"` 属于正常现象，因为它的 API key 认证不由 Codex 管理。

匿名 Context7 弹出的认证提示会暂停当前工具调用，不代表认证 fallback 已经执行。先处理或关闭提示，让调用返回后路由才能继续。

<a id="temporary-context-waiver"></a>

## 原生上下文管理临时豁免

正式 Improve 规划缺少原生上下文管理时，请检查会话实际提供的工具，并保留已有配置。不要为绕过此次不可用而编辑本地配置、反复切换功能开关、修改技能或重建环境。

如需继续，必须由用户明确授权，仅为某一指定计划及同范围审阅豁免原生上下文管理前置条件。这不是自动或全局豁免：Plan Mode、结构化提问、只读规划和其他权限边界仍须保留。例如：

```text
我批准仅为本计划及同范围审阅豁免原生上下文管理前置条件；保留 Plan Mode、结构化提问、只读规划及其他权限边界。请勿为此修改配置或全局技能。
```

豁免既不会恢复该能力，也不保证规划质量。确认会话实际恢复该能力后，新计划不再需要例外。Default Mode 中的实现、审计和普通生命周期记录不受影响。常规安装设置不是服务暂时不可用的修复办法。

历史背景：**2026-09-12**，Tibo（@thsottiaux）[宣布](https://x.com/thsottiaux/status/2098612714704891959)关闭一项需要主动加入的上下文管理实验，该实验可能导致提前停止或回复较早的消息。仓库保留了[用户提供的截图](evidence/2026-09-12-tibo-context-management.png)作为辅助证据。公告没有点名具体配置项，也不能据此判断某个账户、套餐或客户端当前是否具备该能力。

<a id="reverting-runtime-settings"></a>

## 回退运行时设置

保留无关配置，将 `plan_mode_reasoning_effort` 恢复为先前的值。要禁用这些功能，应明确将 `context_management.experimental_mode`、`code_mode.enabled` 和 `default_mode_request_user_input` 设为 `false`。从覆盖层删除键或回退源码，不会清除已经写入 `config.toml` 的值。

Home Manager 用户还应在激活前撤销托管覆盖层中的对应设置，否则激活时会再次写入托管值。有效配置改变后，按[重新加载说明](../README.zh-CN.md#更新后重新加载)操作。

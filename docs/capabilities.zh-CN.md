# Codex Base 能力目录

本目录区分可移植插件与完整的 Linux Nix/Home Manager 安装。“插件”指
`codex-base@bioinformatist-codex` 安装的内容；“Nix”还包括 Home Manager
模块、软件包、全局配置及无命名空间的技能链接。显式与条件触发是有意设计：
安装本身不会运行任何技能。“插件”和“Nix”两列只说明 Codex Base 会提供或
配置什么。用户也可以自行配置 Mintlify 或 Context7，或通过其他插件获得相应配置。

| ID | 能力 | 插件 | Nix / Home Manager | 触发条件 | 职责 | 验证方式 | 来源 |
|---|---|---|---|---|---|---|---|
| global-agents | 全局 AGENTS 指引 | 否 | 是 | Codex 加载受管的全局指引 | 保存用户长期适用的 Git、Nix、代理、密钥处理、证据与工作偏好；执行器自身的范围、检查、STOP 和交接约束仍留在执行器中 | 检查 Home Manager 生成的 `.codex/AGENTS.md` 并运行 Home Manager 检查 | Codex Base；可移植插件有意不安装此文件 |
| docs-routing | Mintlify / Context7 MCP 配置及路由 | 匿名 HTTP 默认配置及带命名空间的技能 | 本地匿名 Context7、可选的用户级认证 Context7 及无命名空间技能 | 任务需要当前版本的库、SDK、API、CLI 或云服务文档 | 先查 Mintlify Index，再查匿名 Context7，仅在可用且必要时查认证 Context7，最后回退至官方一手资料；只接受相关、版本匹配且来源可追溯的结果，绝不发送私有内容 | 运行插件 schema、smoke、portability 及 Home Manager 检查；Codex 原生同名配置优先于插件默认值 | Codex Base |
| github-mcp | GitHub MCP | 否 | 是 | 需要 GitHub 仓库数据或已获授权的 GitHub 操作 | 提供已配置的 GitHub MCP 连接；其本身不会授予凭据 | 设置 GitHub 令牌文件选项后检查 Home Manager 生成的 Codex 配置 | Codex Base |
| improve | Improve 顾问、执行器与审查器 | 是 | 是 | 插件中显式调用 `$codex-base:improve ...`，或在 Nix 环境调用 `$improve ...`；正式规划使用具备原生上下文管理和结构化提问能力的内置 Plan Mode，而实现、审计和普通生命周期记录不受此规划门槛限制；如暂时缺少原生上下文管理，请参阅须由用户授权的[单计划临时豁免](../README.zh-CN.md#temporary-context-waiver) | 先查清事实，只询问仍未确定且影响实质结果的选择；在对话中给出完整的替换计划且不写文件；仅在之后获准的阶段持久化或委派；逐步简化并管理审查与检查点边界 | 以只读方式运行 `$codex-base:improve quick`；Nix 另提供 `codex-improve-*` 命令和 `$improve` | 改编自 [shadcn-improve](https://github.com/shadcn/improve)，由 Codex Base 维护 |
| executor-routing | 按明确规则选择执行通道 | 是 | 是 | 已审查的计划已经确定产品、架构、兼容性与实现决定，并列出准确路径和检查 | `.16` 的合格 Spark 通道在每次调用前查询原生元数据：Spark 有额度时选 Spark，否则选低推理强度的 Luna；查询出错即停止，已启动的调用不换模重放。旧计划仍固定使用 Spark；standard/deep、审查和 scout 角色不变。不自动分类任务，也不承诺不限量 | 检查 `src/improve/config/roles.json`、规划契约的 Executor routing 章节及执行器测试；另见官方 [Codex-Spark 用量限制](https://learn.chatgpt.com/docs/agent-configuration/speed) | Codex Base |
| early-simplification | 尽早验证并简化 | 是 | 是 | 计划步骤修改代码或测试；实现完成后再做最终审查和按风险触发的审查 | 每个改动步骤先验证，再在当前进程中检查多余复杂度；最后运行一次 Ponytail，并只在相应风险存在时追加独立的正确性或优雅性审查 | 检查计划中的步骤验证和审查记录，再运行其中的确定性检查 | Codex Base |
| grilling | Grilling | 是 | 是 | 显式要求在行动前追问、访谈或压力测试某项决定 | 以短轮次追问尚未解决且会实质影响结果的决定，保留已定选择，不自动开始实现 | 对临时决定调用 `$codex-base:grilling` 或 Nix `$grilling` | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |
| ponytail-review | Ponytail Review | 是 | 是 | 显式要求审查差异中的过度工程 | 找出可以删除或改用原生机制的受支撑复杂度，同时保留已接受的接口、行为与必要测试；不据此批准正确性或发布 | 对小型差异调用 `$codex-base:ponytail-review` 或 Nix `$ponytail-review` | 改编自 [ponytail](https://github.com/DietrichGebert/ponytail)，加入 Codex Base 的保留与报告规则 |
| ponytail-audit | Ponytail Audit | 是 | 是 | 显式要求审计整个仓库的过度工程 | 审计全仓库的受支撑复杂度，不直接修复，也不把行数当作评分；不据此批准正确性或发布 | 调用 `$codex-base:ponytail-audit` 或 Nix `$ponytail-audit` | 改编自 [ponytail](https://github.com/DietrichGebert/ponytail)，加入 Codex Base 的保留与报告规则 |
| ponytail-debt | Ponytail Debt | 是 | 是 | 显式要求收集 `ponytail:` 注释 | 生成刻意捷径及其重访条件的只读台账，不写入或暂存台账文件 | 在仓库中调用 `$codex-base:ponytail-debt` 或 Nix `$ponytail-debt` | 改编自 [ponytail](https://github.com/DietrichGebert/ponytail)，加入 Codex Base 的保留与报告规则 |
| diagnosing-bugs | Diagnosing Bugs | 是 | 是 | 已有具体的疑难缺陷、回归、偶发失败或性能症状，需要定位根因 | 建立紧密复现循环、收窄假设并保留脱敏证据；只要求诊断并不授权修改源码或添加生产环境插桩 | 带具体症状调用 `$codex-base:diagnosing-bugs` 或 Nix `$diagnosing-bugs` | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |
| tdd | TDD | 是 | 是 | 用户显式要求测试先行，或要求先写回归测试再修复 | 在已确定的公共边界上按红—绿—重构推进行为 | 针对一次临时行为变更调用 `$codex-base:tdd` 或 Nix `$tdd` | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |
| codebase-design | Codebase Design | 是 | 是 | 需要设计模块边界、接口、接缝、适配器或可测试性 | 用统一的模块与接缝词汇比较接口；仅在已获委派授权且工具可用时使用子代理，否则在当前会话中比较可行方案 | 对一个接口调用 `$codex-base:codebase-design` 或 Nix `$codebase-design` | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |
| domain-modeling | Domain Modeling | 是 | 是 | 正在修改术语表、统一语言或持久架构决策 | 收敛领域语言；仅在获准写入时更新术语表或 ADR，否则在对话中给出完整的拟议改动 | 修改领域术语时调用 `$codex-base:domain-modeling` 或 Nix `$domain-modeling` | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |
| merge-conflicts | Resolving Merge Conflicts | 是 | 是 | Git 在进行中的合并或变基里报告未解决冲突块 | 在保留双方意图的前提下解决现有冲突并验证结果 | 只在可丢弃的冲突仓库中调用 `$codex-base:resolving-merge-conflicts` 或 Nix `$resolving-merge-conflicts` | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |
| playwright | Playwright 技能 / CLI | 仅技能 | 技能及 CLI 可执行文件 | 请求浏览器检查或 Playwright 自动化；只有 PATH 上已安装二进制时才会使用 CLI | 提供无头优先的浏览器工作流；只有 Nix / Home Manager 完整环境安装 `playwright-cli` 可执行文件与 Node 运行时 | 调用 `$codex-base:playwright-cli` 查看指引；在 Nix 环境另运行 `command -v playwright-cli` | 改编自 [playwright-cli](https://github.com/microsoft/playwright-cli) |
| stop-slop | stop-slop | 是 | 是 | 技术事实确定后，需要对可发布文字做最终编辑 | 在不改变命令、标识符、事实与限定条件的前提下移除套路化措辞 | 对临时文本调用 `$codex-base:stop-slop` 或 Nix `$stop-slop` | 改编自 [stop-slop](https://github.com/hardikpandya/stop-slop) |
| handoff | Handoff | 是 | 是 | 显式要求为另一会话准备续接材料 | 获准写入时，在临时目录生成一份脱敏且不重名的交接文件；禁止写入时，在对话中给出完整交接，不创建文件 | 用临时上下文调用 `$codex-base:handoff` 或 Nix `$handoff`，检查返回的临时路径或对话输出（按当前模式） | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |
| wait-what | Wait What | 是 | 是 | 在插件中显式调用 `$codex-base:wait-what`，或在 Nix 环境调用 `$wait-what` | 使用当前对话的语言改述材料，保留事实、约束、限定条件与不确定性，且不创建文件 | 对可丢弃的难懂文字调用任一形式并检查对话回复 | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |
| questionnaire | To Questionnaire | 是 | 是 | 显式要求生成一份交给他人回答的问卷 | 获准写入时，生成一份安全且不重名的临时 Markdown 问卷；禁止写入时，在对话中完整输出。任何情况下都不代为发送或索要密钥等秘密值 | 用临时知识缺口调用 `$codex-base:to-questionnaire` 或 Nix `$to-questionnaire`，核验输出模式 | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |
| writing-agents | Writing for Agents | 是 | 是 | 正在编写技能、`AGENTS.md` 等大段供智能体读取的指引 | 让智能体指引易于发现、边界清晰且节省上下文 | 对临时指引调用 `$codex-base:writing-for-agents` 或 Nix `$writing-for-agents` | 改编自 [mattpocock-skills](https://github.com/mattpocock/skills) |

准确的来源与许可证信息见[致谢](credits.md)。修订版本与收录路径仍以
`vendor/sources.json` 为机器可读的唯一事实来源。

当远端 GitHub CI 成为唯一剩余步骤时，最多查询一次状态，然后报告准确的 head、运行链接和剩余验收项。仍在等待的检查必须如实标为 pending，不能算作通过。只有用户明确要求监控时，才继续跟踪、轮询或安排后续检查；授权不依赖特定措辞或语言。

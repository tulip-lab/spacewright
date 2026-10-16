# SpaceWright 四项代码审查问题修复方案

- 日期：2026-10-17（Australia/Melbourne）。
- 审查基线：`develop@e40cd009c2771f3496fe075500f22ed55fef5ec9`。
- 初始交付（实施前）：修复方案文档；当时尚未修改实现、添加正式回归测试或提交。实施结果见文末。
- 用途：后续明确要求“执行本文方案”时，作为本轮修复范围与验收依据。
- 既有三份 10 月 15–16 日审查文档为历史背景。本轮编号 R1–R4，不与上一轮 F1–F3 混用，也不要重复实施已合入的修复。

## 1. 可直接交给 Codex 的执行指令

> 请执行本文 R1–R4 修复，补充能暴露旧行为的回归测试，并完成针对性验证和一次最终完整检查。
>
> 开始前读取当前 AGENTS.md，检查 HEAD、分支和工作区。若基线已变化，按函数和调用链重新确认问题是否存在；不要重置、覆盖用户工作或重复修复。本文行号只适用于记录时基线。
>
> 可写范围为 SpaceWright 内与四项问题直接相关的模式预检、配置服务、前端恢复交互、配置代次检查、测试及必要文档。不要修改 Mackup、真实用户配置、机器绑定、显示 profiles 或系统设置。保留已有未跟踪文档。不委派子代理。
>
> 实现工作遵守仓库 feature/* 分支规则：复用合适的当前 feature 分支，否则从合适的 develop 基线创建一个聚焦的 feature 分支；不创建额外 worktree。保持每项修复可独立审查和回退。
>
> 按 R1 → R2 → R4 → R3 推进；R4 和 R3 可共享最小必要诊断 helper，但回归断言和完成状态分别报告。先用正式测试证明旧行为失败，再修复。不要通过改坏默认配置、放宽确认或身份检查、忽略写 guard、关闭诊断检查来消除失败。
>
> 所有可能触及桌面入口的测试，包括 dry-run 与浏览器测试，必须经过仓库隔离执行器，使用临时配置和模拟后端。不得运行真实显示切换、窗口或 Space 修改、应用激活、yabai 重启；不得因待修复命令声称支持 dry-run 就绕过隔离。
>
> 本任务授权实现修复与验证。没有明确要求“提交修改”时，不自行提交、合并、推送或发布。交付时报告各问题状态、修改文件、旧行为失败与新回归结果、完整检查结果，以及仍未验证的真实硬件和桌面行为。

## 2. 问题与已复现证据

| ID | 优先级 | 问题 | 审查中的复现结果 | 主要位置 |
| --- | --- | --- | --- | --- |
| R1 | P1 | 模式预检把可省略字段的匹配条件当成真实拓扑键 | 仓库 v3 示例校验通过，普通 `resolveV3` 解析为 `built_in`，但公开 `mode solo --dry-run` 返回 1，误报 setup 未确认或缺少绑定 | `state-cli.mjs:65–81` 的 `transitionResolution`；`config-v3.mjs` 的匹配与确认逻辑 |
| R2 | P2 | 历史快照恢复没有当前配置 revision 门禁 | 读取旧快照后保存较新配置，无 revision 的恢复请求仍返回 200，并将配置改回旧内容 | `server.mjs:583–587`；`public/app.js:936` |
| R3 | P2 | 运行时诊断只比较源摘要 | 清空 runtime 的 `workspaces`，保留旧 `generated` 后，诊断仍返回 `compiled_runtime.ok: true` | `server.mjs:677–683,716`；`config-store.mjs` 的 `generationDocument` |
| R4 | P2 | 无效 v3 配置使诊断接口空引用崩溃 | 将窗口的 app 改为不存在的引用后，诊断返回 500：`Cannot read properties of null (reading 'hardwareProfileId')` | `server.mjs:663–715` |

以上复现使用临时文件、模拟 yabai 和隔离进程，没有改变真实桌面。

审查时完整隔离检查通过：262 项 Node 测试、Fish 语法与配置 fixtures、安装卸载、发布打包和 smoke；`git diff --check` 通过。这是修复前基线，不能证明四项遗漏已解决。

## 3. 共同约束

1. 保留公开命令、v2/v3 配置格式、当前机器确认记录及正常保存/恢复行为；本轮不新增配置版本或迁移机器状态协议。
2. 沿用 `stableRead`、`generationDocument`、配置写事务、执行租约、总 deadline 与取消机制。仅在减少实际重复时提取 helper，不重构整个服务。
3. 读到不完整或不一致状态时明确拒绝或报告不可验证；不能回退到 starter、v2 或“正常”状态掩盖活动配置问题。
4. 只读诊断不得修复文件、重新编译并写入 runtime、更新确认、启动应用或重启服务。
5. 避免把历史快照恢复扩展成完整 v3 历史系统；活动 v3 时继续拒绝旧 v2 历史恢复。
6. 不给本文新增执行进度文件、项目管理目录或测试框架。后续执行完成可在本文末尾补充实际结果，不覆盖基线证据。

## 4. R1：兼容可选匹配字段的模式预检

### 4.1 根因与目标

`topologyKey` 针对真实显示描述计算 `kind:orientation`。默认 MacBook 的内屏条件只有 `{ role: 'built_in', kind: 'built_in' }`，合法省略 `orientation`。直接对条件调用 `topologyKey` 会生成 `built_in:undefined`，与确认时保存的 `built_in:wide` 不一致。Sidecar 条件及 `allowAdditionalDisplays` 也需要核对，不能只给内屏补一个常量。

目标：合法、已确认、物理绑定有效的目标 setup 可以通过显示前预检；真正未确认、物理绑定失效或目标不唯一的情况仍在修改前拒绝。

### 4.2 实现要求

- 移除 `transitionResolution` 中以 `topologyKey(setup.match.displays)` 直接查确认记录的假设。优先在 `config-v3.mjs` 复用或提取纯匹配 helper，让普通解析与切换预检遵循同一套可选字段、数量和显示集合语义。
- 目标候选须同时满足目标 compatibility mode、已确认硬件 profile、现有确认记录、当前连接的物理显示与角色绑定。不能只凭 `activeSetup`、setup 存在或唯一候选就视为已确认。
- 将 setup 条件与**已确认的具体拓扑**匹配：未声明的 kind/orientation 按既有匹配语义处理；声明的字段仍严格约束。需要解析确认键时，应校验其结构并使用一对一集合匹配，不能按数组顺序、字符串替换或补 `undefined` 实现。
- 目标方向可以与当前方向不同，不能要求当前实时拓扑已等于目标，否则 wide/tall 切换会被阻断。当前快照用于核验物理身份、显示类型、数量、绑定和可提前验证的窗口条件；显示后的真实快照负责最终解析和方向确认。
- `allowAdditionalDisplays` 允许的额外显示必须符合实际连接集合与已确认具体拓扑，不能在匹配时无条件丢弃额外显示。多种 setup 或目标拓扑仍无法唯一确定时明确拒绝，不任取第一个。
- 若同一宽泛 setup 有多个确认拓扑，先说明现有 mode/profile 能否唯一确定目标；无法确定时保留明确拒绝。不引入自动确认或新的猜测规则。
- 保留已有显示前配置/机器代次复核、租约、取消和 deadline，显示 profile 只执行一次。显示后继续用真实快照 `resolveV3`，核对目标 setup 和身份连续性。
- 不通过修改 starter/example，强制所有匹配条件都声明方向来绕过兼容性问题。

### 4.3 验收

| 场景 | 必须断言 |
| --- | --- |
| 原样 starter 与仓库示例的 MacBook 内屏，方向省略 | schema/语义校验通过，普通解析与模式预检一致，不再误报未确认 |
| MacBook 内屏 + wide/tall，以及带 Sidecar 的受支持组合 | 可选方向字段正确匹配；模拟切换后用真实新快照完成解析 |
| 目标条件省略 kind 或允许额外显示 | 复用既有匹配语义；有唯一已确认目标时通过，否则给出准确拒绝原因 |
| wide → tall 与 tall → wide，均已确认 | 不要求旧方向等于目标；模拟 profile 一次，布局使用新几何 |
| 缺少目标确认、错误绑定、重复绑定、显示断连、多个目标 | 显示与布局修改次数均为 0 |
| 预检后配置/机器变化、取消、超时 | 继续保留原有拒绝行为，无后续修改 |
| 公开 `spacewright mode solo --dry-run` | 穿过真实入口，成功生成只读计划，无 journal、banner 或桌面修改 |

建议位置：`configurator/lib/config-v3.mjs`、`configurator/state-cli.mjs`；既有 `config-v3.test.mjs`、`review-remediation.test.mjs`、`state-cli.test.mjs` 或对应现有测试。至少覆盖一次公开入口及一次模拟执行，不能仅测试新 helper。

## 5. R2：历史恢复增加 revision 门禁

### 5.1 API 与事务

- `POST /api/history/:id/restore` 要求请求携带 `baseRevision`。缺失返回 428；当前 revision 不一致返回 409 和稳定的冲突 code；沿用当前配置 revision 算法。
- revision 表示用户审阅/确认所依据的活动配置。不能在真正提交前自动获取最新 revision 并悄悄重试，否则仍会覆盖用户没看过的新保存。
- 在 `serializeConfigWrite` 内重新检查活动版本、读取当前配置和比较 revision，然后读取、验证待恢复快照并在内存完成编译。首个持久化动作之前完成所有可预知的业务检查。
- 活动 v3 时继续返回明确的 409，零配置/runtime 写入，不让 v2 历史覆盖活动 v3。
- 在恢复入口显式执行与历史快照 GET 路由相同的 ID 格式校验（当前恢复入口尚无该校验）；不存在、损坏或无效快照分别返回明确错误。锁外存在性检查不能替代锁内读取。
- 成功恢复前保留当前配置的恢复快照；写入恢复配置与匹配 runtime 后，在锁内回读并核验源内容、版本和生成内容一致。不要仅检查 HTTP 状态。
- 业务拒绝发生在首次持久化之前，须释放写 guard；部分写入或回读失败须抛错并保留 guard，继续阻止读者使用混合代次。
- 成功响应应在事务完成后发送；活动日志写入失败须与配置写入失败区分，不让前端误以为已经成功的恢复完全没有发生。

### 5.2 前端

- 历史恢复在进入比较流程或打开恢复确认框时固定当前页面所依据的 `state.serverRevision`，请求必须发送该固定值，不能在异步确认后读取可变状态中的较新 revision。
- 409 时保留当前草稿，提示重新加载并比较；不得自动重试、清空草稿或显示恢复成功。428 不应在正常 UI 流程出现。
- 恢复成功后同步 config、savedConfig、revision、source、dirty 状态，并清理旧运行计划、预览与捕获缓存，避免继续执行恢复前的计划。
- 保持活动 v3 时历史恢复按钮不可用，且后端独立检查，不只依赖 UI。

### 5.3 验收

| 场景 | 必须断言 |
| --- | --- |
| 正确 revision 恢复 v2 快照 | 内容与快照一致，runtime 同代；恢复前内容可从约定快照找回 |
| 无 baseRevision | 428；配置、runtime、历史文件字节不变，无 guard 残留 |
| 页面 A 审阅恢复，页面 B 先保存，A 再提交；包括确认框打开期间发生保存 | 409；B 的内容不变，A 草稿保留；请求仍使用确认前固定的 revision |
| 相同旧 revision 的两个并发恢复/保存 | 只有符合串行 revision 检查的请求成功，其余冲突；用不同内容保证 revision 真正变化 |
| 活动版本在等待写锁期间切为 v3 | 锁内拒绝，不能污染共享 runtime |
| 快照 ID 非法、不存在、损坏、校验失败 | 明确拒绝，首个配置持久化动作之前失败；配置、runtime 与历史字节不变，无 guard 残留 |
| runtime 写入失败或回读不符 | 不返回成功，保留 guard，普通读取 fail closed |
| 浏览器成功恢复后再次编辑保存 | revision 更新正确，旧预览不再可执行 |

建议位置：`configurator/server.mjs`、`configurator/public/app.js`；`server.test.mjs`、`server-v3.test.mjs`、`configuration-round-trip.test.mjs` 及必要 API 文档。

## 6. R4：诊断按依赖状态生成结果

先做 R4，为 R3 提供明确的“可计算预期 runtime”前置状态。

- 将配置读取/验证、硬件 setup 解析、预期运行时生成、保存运行时核验、桌面状态比较各自的前置条件表达清楚。无需引入大型状态机。
- v3 校验失败时，`schema` 为失败并带实际校验原因；`hardware_setup` 与 `compiled_runtime` 明确标记“因配置无效不可验证”，不能访问空 resolution 或显示正常。
- 保留 `checks` 中既有 `id/ok/detail` 契约。建议无法验证使用 `ok: null`，确认异常使用 `ok: false`；如新增 reason/code，保持可向后兼容并核对前端渲染。
- 只有真正存在 resolution 才读取 profile/setup 字段；只有有效 v2 投影存在且相关发现完整时才计算 reconciliation，不能对未解析 v3 访问 `config.modes`。
- 配置有效但 setup 未确认、绑定过期、硬件解析失败、发现不完整时，也应返回准确的失败/不可验证检查。不能因“校验有效”就声称硬件解析成功。
- 对预期业务异常返回结构化诊断，建议 HTTP 200 表示诊断请求已完成，健康状态由 checks 表达；保留认证/来源拒绝及真正非预期服务错误的原有错误语义。
- 核对无效 JSON/读取失败的入口：若纳入结构化诊断，使用明确加载失败结果，不能推断未知版本或回退默认配置。至少保证本轮已复现的 v3 语义错误稳定返回具体原因。
- 配置或 runtime 不可验证时，`null === null` 不能构成“正常”的判据。

验收至少包括：未知 app 引用、其他 schema/语义错误、合法但未确认 v3、绑定失效、完整/部分/不可用发现、正常 v2/v3。业务错误不得产生空引用或未处理异常；前端能展示失败原因，诊断前后配置/机器/runtime 字节不变，无桌面修改。

建议位置：`configurator/server.mjs` 的 `/api/diagnostics`；必要的小型诊断 helper；既有服务测试及一个代表性诊断页面交互检查。

## 7. R3：核验完整运行时代次与内容

### 7.1 预期文档与读取一致性

- 用活动配置的实际源字节生成预期文档，复用 `generationDocument(config, resolution, source)`。不要使用格式化后的 JSON 替代原始 source，否则仅缩进变化就会与真实编译缓存产生错误比较。
- 配置、机器状态与 runtime 的读取遵循 guard 和代次边界。guard 存在、读取前后 source/machine/活动版本发生变化，或无法建立一致视图时，报告正在写入/不可验证，不能显示绿色。
- 复用 `stableRead` 与必要的前后核验，不给只读诊断获取写锁或引入另一套长期锁协议。
- v3 的预期上下文使用本次诊断的明确 machine/hardware/display 数据。将首次稳定读取的 machine 显式传给发现过程，不能沿用内部另读 machine 的 querySnapshot() 路径；不要在 helper 中重新发现另一份上下文后与旧快照混用。增加发现期间绑定变化的回归，要求返回不可验证。

### 7.2 检查内容

至少同时验证：

1. 文件存在、JSON 可解析，runtime 与 `generated` 结构有效。
2. `format_version`、`compiler_version`、`source_version` 与当前预期一致。
3. `source_sha256` 与实际活动源字节一致。
4. 对去除 `generated` 后的实际 runtime 正文重算摘要，与保存的 `runtime_sha256` 一致；再与当前编译所得正文/预期摘要比较，防止正文和自报摘要一起改写仍被视为正确。
5. `context_sha256` 与当前预期一致，v2 的空上下文也沿用正式生成算法。
6. `generation_id` 与正式生成算法及当前预期一致。

不复制一套散落的编译版本常量和摘要算法。可以在 `config-store.mjs` 提取小型只读核验 helper；需明确对象键顺序与序列化契约，避免拿文件缩进或尾部换行当正文完整性标准。以现有生产者的摘要算法为准，不在本轮悄悄改变缓存格式。

### 7.3 诊断表现与验收

- 缺失、坏 JSON、正文不符、源过期、上下文过期、编译器版本过期分别提供可操作原因；多个问题可合并展示，但不能仅说 source 当前。
- 只有全部必需条件成立才返回 `compiled_runtime.ok: true`。预期文档无法计算时沿用 R4 的不可验证状态，不声称缓存健康。
- 诊断只报告，不自动保存或修复缓存；需要重编译时提示现有正式入口。

| 场景 | 必须断言 |
| --- | --- |
| 正常 v2/v3 runtime | 为正常，使用与正式生产者一致的摘要 |
| 清空 workspaces，保留 generated | 完整性失败，不能返回 true |
| 正文及自报 runtime_sha256 一起改写 | 与正式编译结果不符，不能返回 true |
| source、编译器版本、source_version 或 generation_id 被替换 | 明确失效 |
| v3 机器绑定、相关显示几何或硬件上下文变化 | 上下文失效，不只比较 source |
| 源文件使用合法非默认缩进并据此正式生成 runtime | 正常；不因为重新格式化 source 误报 |
| runtime 缺失、JSON 损坏、generated 缺字段 | 失败且有准确原因，不出现误绿或接口崩溃 |
| 有效配置无法解析 setup，或存在写 guard/并发代次变化 | 不可验证，无写入、无桌面修改 |

建议位置：`configurator/lib/config-store.mjs`、`configurator/server.mjs`；`server.test.mjs`、`server-v3.test.mjs` 或既有代次测试。测试由真实 `generationDocument` 建立健康对照，再逐项破坏，不能只手工构造一个永远返回失败的样本。

## 8. 执行与验证流程

### 8.1 每项修复

1. 读取现状并建立最小回归。先在旧实现上确认关键断言失败，记录具体失败原因。
2. 完成实现、调用方和必要文档修改。R1 不改配置掩盖问题；R2 同步前后端；R3/R4 共用的诊断路径一并核对。
3. 通过隔离执行器运行相关测试。每项通过后继续，避免对未变化内容反复跑完整检查。
4. 对改变的 Fish 文件运行 `fish -n`；若最终完整检查已覆盖，无需再重复。

针对性调用示例（按实际修改的测试文件调整）：

```sh
node scripts/isolated-check.mjs node --test configurator/test/config-v3.test.mjs configurator/test/review-remediation.test.mjs
node scripts/isolated-check.mjs node --test configurator/test/server.test.mjs configurator/test/server-v3.test.mjs
node scripts/isolated-check.mjs node --test configurator/test/configuration-round-trip.test.mjs
```

不要从隔离环境外启动浏览器所连的真实配置服务。模拟进程、HTTP 服务、就绪等待与清理均须有界；并发测试用就绪信号安排竞态，不靠随意 sleep 猜测时序。

### 8.2 最终统一检查

```sh
fish scripts/check.fish
git diff --check
git status --short
```

- 确认新增测试使用现有 `*.test.mjs` 约定，确实被完整检查收集。
- 检查一次历史恢复冲突与一次诊断错误展示；没有布局变化时不扩展为多视口视觉测试。
- 检查无关文档和用户修改未被覆盖，临时进程/配置已清理。
- 若完整检查失败，报告实际原因与影响；不得以基线 262 项曾经通过替代修复后的结果。

## 9. 完成交付标准

- R1：默认 MacBook、可选字段及已确认切换正常；缺确认/绑定错误/歧义仍在显示修改前拒绝；模拟 profile 一次，显示后重新解析真实状态。
- R2：缺 revision 与过期恢复被拒绝；成功恢复同代、可回退；部分写入保留 guard；前端冲突不丢草稿。
- R4：无效 v3 及无法解析的 setup 返回具体诊断，无空引用；依赖状态不能误绿。
- R3：正文完整性、源、版本、上下文与代次全部核验；损坏 runtime 无法伪装成健康；诊断不修改文件。
- 报告每项旧行为失败证据、新回归通过证据、修改文件和最终完整检查结果。
- 明确剩余限制：模拟检查不代表真实 displayplacer、macOS 窗口/Spaces、Sidecar 或全部硬件组合已经实测；本轮没有发布、完整 v3 历史系统或新机器确认协议。
- 如用户后续明确要求“提交修改”，按 AGENTS.md 的完整交付含义执行，并在 staging/commit 前重查文件边界与工作区；否则止于修复、验证和汇报。


## 10. 实施结果（2026-10-17）

本轮依据用户明确要求先修订方案，再执行实现与验证；工作分支为
`feature/review-fixes-2026-10-17`，基线仍为本文记录的 `e40cd00`。
实现与验证阶段未提交、合并、推送或发布；后续 Git 交付按用户另行明确授权执行。其他三份未跟踪审查文档保持原状。

### 10.1 审查补充与实现

- R2 在比较开始或恢复确认框打开时固定 revision，并在恢复入口新增与 GET 路由相同的 ID 格式校验。浏览器回归同时覆盖另一页面保存，以及同一页面在恢复确认期间保存、更新可变 revision 的情形。
- R3 将同一次稳定读取所得的 machine 显式传给发现过程；发现、源、活动版本、runtime 或机器代次变化均返回不可验证。

| 问题 | 实际修复 | 主要修改文件 |
| --- | --- | --- |
| R1 | 通过共享一对一集合匹配验证已确认具体拓扑，兼容省略 kind/orientation；完整核验额外显示与物理绑定，拒绝多个确认目标；普通解析支持同一物理显示在不同 setup 中使用不同角色，保留过期绑定诊断 | `configurator/lib/config-v3.mjs`、`configurator/state-cli.mjs` |
| R2 | 锁内检查活动版本与 revision，读取、验证、预编译快照；创建恢复点后写入并回读核验源与 runtime；失败 guard 及日志警告分别处理；前端冲突保留草稿、成功更新 revision 并清理计划和预览 | `configurator/server.mjs`、`configurator/public/app.js` |
| R4 | 将验证、完整发现、setup 解析与运行时检查的前置条件分开；无效配置及未确认或失效绑定不再空引用；无法验证时显示 `ok: null` 和具体原因 | `configurator/server.mjs` |
| R3 | 使用实际源字节和同一份明确上下文生成预期文档，核验正文自报摘要、正式编译正文、全部正式元数据及 generation；前后复核源、机器、活动版本、runtime 和 guard | `configurator/lib/config-store.mjs`、`configurator/server.mjs` |

测试修改：`configurator/test/config-v3.test.mjs`、
`configurator/test/review-remediation.test.mjs`、新增
`configurator/test/code-review-fixes.test.mjs`。API 与诊断说明更新于
`docs/configurator.md`；方案修订与实际结果保留于本文。

### 10.2 旧行为失败证据

| 问题 | 正式回归在旧实现上的结果 |
| --- | --- |
| R1 | 在隔离执行器内解包原始 HEAD 的临时基线副本，并使用修正为原生 `is-built-in` 字段的测试；starter 和 example 的公开 `mode solo --dry-run` 均返回 1，误报目标歧义、未确认或缺少绑定；2 项回归失败。临时基线副本已删除 |
| R2 | 无 baseRevision 的恢复返回 200，期望 428；注入 runtime 回读正文不符时仍返回 200，期望 500 |
| R4 | 未知 app 返回 500、空引用 `hardwareProfileId`；合法但未确认的 setup 返回 500、空引用 `solo` |
| R3 | 清空 runtime 正文、保留 generated 后仍返回 `ok: true` 和 `source digest is current`；正式生成的四空格缩进健康源反而被标记 stale |

### 10.3 验证结果

- 针对性测试：配置匹配、历史恢复 API、浏览器交互、诊断依赖状态与完整性共 96 项通过；另外单独验证了原有硬件代次/过期绑定测试、双向模拟显示切换、MacBook 公开 dry-run 与模拟执行。
- 所有涉及公开入口、HTTP 服务、浏览器或模拟修改的测试均通过 `scripts/isolated-check.mjs`，使用临时配置和模拟后端。新增服务 fixture 的请求和清理有时限，竞态测试通过明确就绪信号控制。
- 第一轮完整检查运行 349 项，346 通过、3 失败：两项是过期绑定错误语义提前退化为 topology unmatched，一项是发现不可用时 runtime 坏 JSON 的具体原因被覆盖。已修正根因，原断言保持不变，相关针对性检查通过。
- 最终完整检查：`fish scripts/check.fish` 返回 0，349 项 Node 测试全部通过、0 失败；相比基线新增 87 项。Fish 语法、v2/v3 schema 与配置 fixtures、Fish 规划/模式/绑定、安装卸载、release archive/checksum/Homebrew formula rendering 以及完整 smoke 均通过，结尾为 `result=ok` 和 `OK SpaceWright release checks`。
- `git diff --check` 通过；新增测试文件及本文的空白检查通过。最终文件范围与授权范围一致，未修改其他三份历史审查文档；实现与验证收尾时未暂存任何文件。临时基线副本与测试 fixture 均已清理。

### 10.4 剩余限制

未执行真实 displayplacer、应用激活、窗口/Spaces 修改、Sidecar 或真实硬件切换。
模拟验收不代表这些桌面与硬件组合已经实测。本轮未发布，未新增完整 v3
历史系统或机器确认协议；宽泛 setup 对应多个已确认目标拓扑时仍明确拒绝，
不会猜测方向或自动确认。

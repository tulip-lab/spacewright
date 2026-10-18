# SpaceWright 统一代码审查与修正记录

- 审查日期：2026-10-19（Australia/Melbourne）。
- 审查基线：`develop@0d9251dc35faf660bb909377dde6956d50fb3164`。
- 原审查阶段只整理文档、审查源码并运行隔离检查。2026-10-19 后续修复及正式回归已完成；用户随后明确授权提交、合并并推送至 `develop`。版本发布和真实桌面操作不在本次范围内。
- 基线确认 **5 项问题：1 项 P1、4 项 P2**；SW-01—SW-05 均已实现修复并通过定向隔离回归。实施、验证及剩余边界见第 6 节；历史编号不再复用。
- 本文吸收三轮代码审查、独立复审及更早的架构加固交接，取代原五份文件。旧文档的执行指令、保留旧报告要求和历史测试计数均不再作为当前指令。

## 1. 为什么以前审查仍遗漏问题，以及如何改进

用户仍需在实际使用中纠正问题，说明此前的审查覆盖不足。旧报告本身也记录了：166、217、262 项测试通过时，仍有对应的已复现缺陷。这些历史计数说明测试覆盖范围，不能证明运行可靠。

从本轮证据可以确认的审查盲区是：

1. **修复停在已发现的入口，没有核对同一契约的所有调用方。** setup 的 dry-run 修好了，config-compile 仍会写入；HTTP 的事务拒绝修好了，CLI 编译仍留下锁。以后每个问题都要列出同类入口及共享 helper 的全部调用方，逐一检查，而不是只补上一份复现。
2. **版本优先规则没有贯穿后台路径。** 编辑、导出和执行采用活动 v3，后台监控仍读取 v2。以后对版本迁移使用“v2-only / v3-only / 双版本共存且内容冲突”的矩阵；不能用内容一致的双版本样本证明切换正确。
3. **把消费者检查正确误当作生产者已经正确。** 上轮诊断已能发现错误 source 摘要，但 setup activation 仍生成错误摘要。以后必须检查“真实生产入口写入 → 正式消费者读取”，包括原始字节、机器上下文和后续再次执行，不能只用 helper 手工生成健康样本。
4. **dry-run 只验证了没有副作用，没有验证预检有效。** 显式 workspace dry-run 只是打印固定说明，无法发现真实执行的 blocker。以后同时断言零修改、与真实规划器相同的可执行性、明确的拒绝原因。
5. **模拟与真实后端之间缺少独立核对。** 需要核对实际参数、字段及后置状态，而不是让 mock 直接实现我们想要的行为。本轮调查曾怀疑“应读取后台目标 Space 的 padding”，但查阅 yabai 源码后发现 grid 实际使用显示器活动 Space；该怀疑已撤销，没有混入缺陷清单。
6. **缺少使用流程的完成门槛。** 单步成功不代表“确认 setup → 激活 → 预览 → 布局 → 验证 → 再次执行零变更”可用。以后必须用完整入口链路覆盖正常、失败、取消及重试；精确记录未实测的硬件边界。

改进后的关闭标准：每个问题必须有旧实现失败证据、修复后通过证据、邻近入口核对、失败后文件/锁/任务状态断言。发现已被反驳或证据不足时明确撤回。不要以增加测试数量或再次全绿替代这些证据。

本轮没有用户实际故障的逐条日志，因此不能声称下列五项解释了用户遇到的全部问题，也不能声称完成了所有 legacy Fish 适配器和硬件组合的逐行证明。

## 2. 基线问题与修复状态

下表的问题描述、行号及最小复现均属于修复前基线；五项当前均已修复，修复后的正式证据见第 6 节。

| ID | 优先级 | 已确认问题 | 主要位置（基线行号） | 证据层级 |
| --- | --- | --- | --- | --- |
| SW-01 | P1 | 活动 v3 关闭自动化，wake 仍执行旧 v2 规则 | `configurator/server.mjs:946`，`configurator/lib/automation-monitor.mjs:43–50` | 真实临时服务 + wake 信号 + 模拟任务执行器 |
| SW-02 | P2 | `config-compile --dry-run` 仍持久化 runtime | `bin/spacewright:66–67`，`configurator/cli.mjs:85–97` | 真实公开 CLI + 临时配置 |
| SW-03 | P2 | `config-diff` 失败留下配置锁，修正 JSON 后仍无法读取 | `bin/spacewright:84–86`，`configurator/cli.mjs:89–97` | 真实公开 CLI + 正式 stableRead |
| SW-04 | P2 | 显式 `workspace ID MODE --dry-run` 跳过真实规划，错误返回成功 | `bin/spacewright:232–239` | 真实公开 CLI，与正式规划器对照 |
| SW-05 | P2 | v3 setup 激活对未重写的源文件使用重新格式化后的摘要 | `configurator/server.mjs:214–215,495–503`；同类调用见正文 | 真实激活 HTTP API + 保存 runtime 摘要核对 |

### SW-01：阻止非活动版本的规则触发任务

**触发与影响：** 同时存在 v2/v3，活动 v3 的 `settings.eventAutomationEnabled=false`，旧 v2 则为 true，并有匹配 wake 的规则。向配置服务发送 wake 后，后台会按旧 v2 的规则下发 `apply coding solo --json`。用户看到的活动配置已经关闭自动化，后台仍产生执行请求。若活动配置也包含该目标且预检通过，后续具备修改桌面的条件。

**根因：** `createAutomationMonitor({readConfig,...})` 注入固定 v2 的读取函数；`monitor.trigger()` 根据该文档检查开关及匹配规则。`activateSetup()` 只覆盖采样的拓扑变更分支，没有覆盖 wake。邻近 `/api/rules/evaluate` 也默认 `readConfig()`，应一并明确版本政策。

**本轮结果：**

```text
activeAutomation=false
legacyAutomation=true
dispatched=["apply","coding","solo","--json"]
tasks=[{target:"coding",status:"completed"}]
```

模拟执行器只写临时标记并返回 `{noop:true}`。这证明实际服务错误下发了任务，不代表运行了真实布局。

**修正边界：** 统一后台入口的活动配置选择及支持的版本。v3 当前 schema 不支持 `rules`，不能简单将 v3 丢给 v2 的 `ruleContext/commandsForExecution`，也不能静默回退读取旧规则。明确拒绝不支持的规则执行，同时保持已确认 v3 setup 的拓扑激活流程。不得为解决本项扩大为新的 v3 自动化配置体系。

**验收：**

- v3-only、双版本共存：wake 不得读取或执行非活动 v2 规则；活动开关关闭时任务数及模拟修改次数均为 0。
- v2-only：关闭开关时不执行；开启后仅执行匹配规则。
- 检查 wake、拓扑事件和手动 `/api/rules/evaluate` 的版本行为，均给出清晰结果。
- 在已确认且可执行的 v3 环境做一次隔离服务回归；不能只用“最终 apply 因缺少确认失败”掩盖错误下发。
- 任务等待期间活动配置改变时，仍核对执行时配置及原有预检；保留总 deadline、取消和 lease。

### SW-02：让配置编译的 dry-run 真正只读

**触发：** 有效 v2 配置下运行 `spacewright config-compile --dry-run`，原先没有 `generated/runtime.json`。

**结果：** 返回 0，打印 `compiled=.../generated/runtime.json`，并创建该文件。

**根因：** 公开入口将选项转交 `cli.mjs compile-to`，但后者解析 flags 后不检查 dry-run，直接取得写 guard 并写文件。

**影响：** 预览会改动持久缓存。调用者不能把它作为零写入检查；存在旧 runtime 时还会覆盖旧文件。

**修正：** 在持久化之前执行与真实编译一致的只读校验，返回明确的预览及目标路径。dry-run 不取得写 guard、不创建目录、备份、runtime 或修复残留锁；未知选项也不能静默执行写入。保持真实编译可用。

**验收：** v2/v3、无已有 runtime/已有自定义 runtime、无效源、未确认 setup、未知选项。用完整目录树和文件字节比较断言零写入，并检查错误退出码。至少一组穿过真实 `bin/spacewright`。

### SW-03：只读 diff 不应阻断后续使用

**触发：** 临时配置写入 `{broken`，运行 `spacewright config-diff`；失败后把配置恢复为有效 JSON，再调用正式 `stableRead`。

**结果：**

```text
config-diff: JSON parse error
.configuration-write remains=true
read after fixing source:
configuration save is incomplete or in progress; refusing mixed generation
```

**根因：** diff 为了生成临时比较文件，调用会锁住源配置目录的 `compile-to`；后者未采用 `trackWrites:true`。即使还没有输出任何内容，读取/解析失败也按不完整写入保留 guard。此外 `or exit 1` 绕过临时 candidate 的清理。

**修正：** diff 应通过正式的只读编译路径取得候选内容，保持配置、机器状态和活动版本的一致读取，再比较临时内容；清理所有退出路径的临时文件。同步审查真正 `compile-to` 的事务阶段：写前拒绝释放自身 guard；已开始持久化后的失败继续 fail closed。不要让 diff 自动删除真实未完成保存的 guard，也不要放松 stableRead。

**验收：**

- 损坏源、无法解析 setup、输出失败、取消：diff 不改变配置/runtime/备份，不留下源 guard 或临时文件。
- 恢复有效源之后无需 repair 即可正常读取、预览。
- 原先存在真实 guard 时仍拒绝读取，不能隐式修复。
- 真正编译中途写入失败保留 guard；成功编译释放 guard。
- 比较相同/不同 runtime 的结果与退出语义有正式断言，不能只检查打印文字。

### SW-04：显式 workspace 预览必须运行真实预检

**触发：** 有效 starter v2、有效 primary 绑定和完整模拟发现，但没有必需的 Code 窗口。

**对照结果：**

```text
spacewright workspace coding solo --dry-run
exit=0
scope=target_only
finalization=none

spacewright apply coding solo --dry-run --json
exit=1
blockers=["required_window_missing"]
```

**根因：** `$plan_args` 仅在自动解析 v3 setup 的分支中设置。v2 显式 mode，以及 v3 显式传入 mode 的 dry-run 会走固定 printf + exit 0，未调用 state-cli。真实执行却会进入 apply。

**修正：** 所有 workspace dry-run 形式复用真实 apply 的只读规划与目标/绑定/窗口预检，保留单工作区范围。自动 setup 路径的预期 setup/profile 校验继续保留。不能以删除 dry-run 支持或仅改文案解决。

**验收：** v2 显式 mode、v3 显式 mode、v3 自动解析三种形式；缺失必需窗、歧义、绑定失效及有效目标。对等输入应得到相同 blocker 和退出码；有效目标输出真实计划；无 banner、journal、配置或桌面写入。保留 optional 缺失的既有语义。

### SW-05：setup 激活生产者必须摘要实际源字节

**触发：** `config.v3.json` 是合法紧凑 JSON，由 starterV3 生成；机器已确认 `mac_mini/single_tall`，绑定与模拟拓扑有效。调用 `POST /api/v3/setup/activate`。

**结果：** HTTP 200、`activated=true`，源文件字节未变；保存 runtime 的 `generated.source_sha256` 却不等于该文件的 SHA-256。

```text
sourceUnchanged=true
actualSourceHash=a20be12b18df70593cd30fc7cce7d6abdec2cad4ee13aa4f07f29c9d63d5e827
compiledSourceHash=59b07f63642f63a0063be38efcfdfadf1af105426d7254795d81f0e0dbe66838
matches=false
```

**根因：** 激活从 `stableRead(...).config` 取解析对象，丢弃 `source`；`compiledV3Document` 默认调用 `serializedConfig(config)`。摘要属于重新格式化的内容，实际却没有重写 portable 文件。使用四空格缩进或不同尾部换行也有同类条件。

**影响：** 正式激活刚生成的 runtime 就与真实源字节不一致；正确的状态/诊断消费者会判定缓存过期。上轮“诊断使用原始 source”修复没有覆盖这些生产入口。

**邻近范围：** setup confirm（483 行）、display bindings（881 行）、后台 topology activation（958 行）也省略 source，静态调用链具有同类缺口。本轮动态证据仅针对 setup activate；不要把其他入口写成已逐一动态复现。正常 v3 save 显式传入其实际保存的 source，不应重复修改。

**修正：** 各入口保存 stableRead 的原始 source，与 config/machine 一致地传入 generationDocument；复核源和机器代次，不能只比较重新序列化后的对象。修改机器时用修改后的预期机器生成上下文。不得为了摘要相等擅自重写用户 portable 配置，或将诊断改回宽松比较。

**验收：**

- 紧凑、二空格、四空格、不同尾部换行的合法源，通过 confirm/activate/bindings/topology producer 分别核对实际摘要。
- 生成后调用正式 runtime 验证及诊断，确认源、上下文、正文和 generation 同时有效；不只检查 HTTP 200。
- 源、机器或活动版本在处理中变化时拒绝使用混合代次。
- 普通保存/备份/历史恢复的原始字节和摘要契约保持正确。

## 3. 历史审查吸收后的判定

旧编号只用于追溯。以下表示当前已有实现和相应回归覆盖，不表示所有相似入口、真实硬件或桌面已被证明正确；新的同类遗漏已在 SW 清单单独列出。

| 历史来源 | 历史发现 | 当前处置/证据位置 |
| --- | --- | --- |
| 10-15 R1 | runtime-id 丢失 dry-run 选项 | `bin/spacewright` 已按参数消耗数转发；`review-remediation.test.mjs` 的 public run 回归 |
| 10-15 R2 | recovery 子进程不登记 lease | `recoveryCommand` 已调用 trackChild；同文件 SIGKILL/INT/TERM/timeout 回归 |
| 10-15 R3 | HTTP 写前拒绝遗留 guard | HTTP 事务已采用 trackWrites；写前拒绝/部分写入回归存在；CLI 邻近遗漏见 SW-03 |
| 10-15 R4 | setup confirm/activate dry-run 写入 | `setup-cli.mjs` 已校验选项并预览；`setup-cli.test.mjs`；编译入口遗漏见 SW-02 |
| 10-15 R5 | v3 导入导出走 v2 | 当前按活动版本读写；`server-v3.test.mjs` 含 v2-only/v3-only/both 往返 |
| 10-15 R6 | 显示变化后继续用旧计划 | 当前有 display phase、稳定发现与新计划关系；`review-remediation.test.mjs` 固定所有权回归 |
| 10-16 F1 | mode 先改显示再校验配置 | 当前经 state-cli 预检、复核代次后执行显示阶段；同文件公开入口及故障注入回归 |
| 10-16 F2 | 活动 v3 备份恢复污染共享 runtime | 当前按 activeDocument、revision 和 backupRevision 恢复并回读；`server-v3.test.mjs` |
| 10-16 F3 | 同应用多窗口捕获选择器相同 | 当前捕获及合并核验选择器；`capture-follow-up.test.mjs` 完整捕获往返与歧义拒绝 |
| 10-17 R1 | mode 预检误用省略字段的 topologyKey | 当前共享匹配并检查确认/绑定；`config-v3.test.mjs`、public MacBook mode 回归 |
| 10-17 R2 | history restore 缺 revision | 当前锁内检查 revision/ID/活动版本、编译与回读，前端固定确认前 revision；`code-review-fixes.test.mjs` |
| 10-17 R3 | runtime 诊断只查 source | 当前 verifyRuntimeDocument 校验正文、元数据及预期 generation；同文件篡改回归；生产者遗漏见 SW-05 |
| 10-17 R4 | 无效 v3 诊断空引用 | 当前按验证/解析/发现依赖生成检查，无法验证为 null；同文件 API/浏览器回归 |

更早的 `architecture-hardening-follow-up.md` 六组要求统一保留为修复约束：固定对象的 Sandbox/清理/排序/后处理；单工作区局部范围；显式应用恢复后重新规划；共享重试及恢复预算；耐久意图/ack 和停止进程后释放 lease；一致配置存储及监控生命周期。当前分别有 pinned-executor、finalization-policy、adapter-preparation、execution-budget、operation-journal/recovery、config-store/automation-monitor 等实现与既有测试。其“尚未实现”的旧措辞已过时，不再照单重新实施；本轮发现监控版本选择仍不完整，见 SW-01。

历史证据边界也保留：最初 smoke 曾有 `libsimdutf.36.dylib` 缺失，后续未复现，未建立产品根因，不列为待修复缺陷；更早测试曾存在落入真实 yabai 的隔离事故，是否产生实际效果未确认。本轮不把它们视为真实功能验收，也不为此修改系统或桌面。

被吸收并删除的文件及原始 SHA-256：

| 文件 | SHA-256 |
| --- | --- |
| `docs/code-review-2026-10-15.md` | `a635aa55f6f29021b56db5d2e07e0ee0d0c361dcd577b820174914205ea1a553` |
| `docs/code-review-remediation-2026-10-15.md` | `43569c9d4f9a30b83c4115c32a06c64db20ffc2beefcabde1a6026d0c7207860` |
| `docs/code-review-follow-up-plan-2026-10-16.md` | `dc2b8ec946144de722f0f9d62bda3f57544fe226d692ed239b2d1e530b858e65` |
| `docs/code-review-fix-plan-2026-10-17.md` | `6f7b058e77217b6ea5784b5a0a403f62717943b6d1c7a8aff16fd409bf457485` |
| `docs/architecture-hardening-follow-up.md` | `425475a83876685ca29823d1abebb9a144b8d5ee6a5d9321674709a84053d6e3` |

保留结论、根因、修复契约和当前回归位置；不继续复制已过时的长调查脚本及互相冲突的执行指令。前三份原为未跟踪文件，已按本次明确要求吸收后删除；其他用户文件未改。

## 4. 本轮采用的修复约束

执行本文时先读 AGENTS.md，核对 HEAD/分支/工作区并重新定位；代码已修复则更新本文件状态，不重复实施。实现按仓库 feature/* 分支规则进行，不改 Mackup、个人配置、安装版本或系统设置，不使用子代理。没有另行要求提交时不自行提交、合并、推送或发布。

顺序建议：SW-01 → SW-02/SW-03 → SW-04 → SW-05。同一 CLI 的两项可以共享小型改动，但分别保留回归证据。不要重写整个运行时、增加新的配置版本或引入新的计划文件。

1. 将附录场景转成现有 `*.test.mjs` 正式断言；证明正确行为在旧实现上失败，再修复。
2. 核对共享 helper 的全部调用方。以“活动版本、原始源字节、事务阶段、dry-run、规划一致性”为契约，检查邻近入口。
3. 通过 `scripts/isolated-check.mjs` 运行所有可能触及桌面入口的检查，包括声称 dry-run 的调用、浏览器和服务测试；只用临时 HOME/配置/状态/模拟后端。不得假定待修代码的 dry-run 已安全。
4. 定向回归检查命令、退出码、文件树/字节、guard、任务和模拟副作用，并核对真实生产者到消费者链路。
5. 修改完成后一次最终 `fish scripts/check.fish`，再 `git diff --check`；有 Fish 修改则确保 `fish -n` 被覆盖。不要重复无变化的完整检查。
6. 仅有用户明确授权真实桌面操作时，才做真实 displayplacer、窗口/Spaces、Sidecar 验收。届时以同一流程的 before/after 和二次执行收敛证明，不能把模拟通过写成硬件通过。
7. **在本文原地更新**每项修复、回归和剩余限制，不再新增“复审/修复计划/实施结果”并行文档。失败后状态不明时保留 fail closed，不放宽身份、确认、lease、guard 或 generation 验证。

## 5. 原审查阶段验证与未覆盖范围

- macOS；Node.js `v26.12.0`、Fish `4.9.3`、jq `1.8.2`，未安装或更新依赖。
- 已读取并核对旧报告、当前公共 Fish CLI、Node 规划/执行/恢复/事务/HTTP/监控链路，以及相应测试。重点是入口契约和实际状态转换；不是所有文件逐行审查。
- SW-01—SW-05 均通过隔离调查复现。调查脚本退出 0 表示调查完成，不代表产品正确。SW-01 任务执行器为临时替身；SW-05 使用模拟显示和硬件探测；均未修改真实桌面。
- 网格疑点经 [yabai 官方 window_manager_apply_grid 源码](https://github.com/koekeishiya/yabai/blob/master/src/window_manager.c#L1920-L1969) 核对后撤回：后端使用显示器活动 Space 的 view。该核对针对上游当前实现，未证明本机安装版本及所有几何开关等价。
- `fish scripts/check.fish` 退出 0：388 项 Node 测试通过，0 失败/取消/跳过；Fish 语法、JSON/schema、v1/v2/v3 fixtures、临时安装/卸载、本地发布包/校验和/Homebrew 生成及 smoke 均通过，结尾为 `result=ok` 和 `OK SpaceWright release checks`。这是未修复五项新问题时的基线结果，不是它们的验收证据。
- `git diff --check`、新增文档的独立空白检查、附录脚本 `node --check` 通过。最终只有新增本文及两份已跟踪旧文档的删除；三份未跟踪旧文档已删除，Git 不显示其删除记录。未修改运行代码、测试或其他文档。
- 未执行真实显示切换、应用激活、窗口/Spaces 修改、服务重启或 Sidecar；未逐项重跑旧报告的已过时附件。用户实际故障日志与全部硬件组合未纳入，不能据此承诺全部问题已找齐或完整回滚已验证。

## 6. 2026-10-19 修复方案与实施证据

本轮在 `feature/review-contract-fixes` 上实现；修改边界为本仓库的公开 CLI、编译/监控/HTTP helper、正式测试及本文。纳入任务开始前两份已被本文取代的旧文档删除，不修改 Mackup、安装版本、个人配置或系统设置，不使用子代理。修复及测试阶段未自行提交；后续提交、合并与推送已由用户明确授权，版本发布不在范围内。

采用的方案依次为：统一活动版本政策；将 compile/effective/compile-to/diff 的候选生成合并到只读 helper，独立控制持久化事务；让所有 workspace 预览进入 apply 规划器；最后沿 confirm/activate/bindings/topology 全部生产入口传递原始 source，并在发现后及保存回读时复核代次。未增加配置版本或自动化体系。

| ID / 状态 | 错误与预期 | 根因对应的修复 | 正式回归与预防 |
| --- | --- | --- | --- |
| SW-01 / 已修复 | 活动 v3 不应执行旧 v2 规则；v2 开关和事件匹配继续有效 | monitor 注入活动配置读取器；wake/dispatch 明确记录 `automation_disabled` 或 `rules_version_unsupported`。手动 rules API 在活动 v3 下返回 409 / `rules_version_unsupported`，即使提交 v2 payload 也不能绕过。v3 拓扑 setup 激活保持独立。规则入队与真正启动子进程前均核对活动配置，并向 apply 传递 `expected-config-digest`，保留原 lease、deadline、取消及规划预检 | `review-remediation.test.mjs` 的 `SW-01`：v2 开/关、v3-only、双版本开/关；已确认、预检可执行的 v3；wake、拓扑及手动 API；排队期间关闭、切换版本、修改规则，仅先前运行中的任务完成，后续任务拒绝且无第二次模拟 dispatch |
| SW-02 / 已修复 | `config-compile --dry-run` 必须执行校验且零持久写入 | 预览走共享只读编译 helper，返回 `dry_run=true`、`mutates=false`、目标路径；不获取或修复 guard。编译相关选项及位置参数在持久化前严格校验；真实编译使用正式原子写入 helper | `SW-02`、`SW-02/SW-03`：v2/v3；runtime 缺失或自定义字节；坏源、坏 machine、未确认 setup、现有 guard、repair+dry-run、未知/无值选项、发现期间源/机器/活动版本变化；比较目录树与文件字节，断言错误退出及零新输出 |
| SW-03 / 已修复 | 失败 diff 不得遗留锁、备份或 candidate；真实中断写入仍须封闭 | diff 将共享只读编译结果通过 stdin 交给 diff，不再创建临时文件或获取写 guard。真实 compile-to 使用 `trackWrites:true`，验证结束前拒绝会释放自己的 guard，开始原子持久化后失败继续保留 guard。已有 guard 不自动修复 | `SW-03`、`SW-02/SW-03`：坏源修复后立即 stableRead；不可解析 machine、未确认 setup、真实 guard、无效比较目标、取消及独立 TMPDIR 空目录；成功编译无 guard，写入失败保留 guard且无遗留原子临时文件。相同 runtime 返回 0 并提示 current；不同 runtime 返回 0 并输出差异；编译/比较错误非 0，保留原公开退出语义 |
| SW-04 / 已修复 | 显式 workspace 预览应与 apply 的 blocker、退出码及计划一致 | 三种入口统一调用 state-cli apply 的只读规划；预览提前进入规划器，保留自动 setup/profile 期望值。参数不再重复传入 mode；范围仍为单 workspace | `SW-04` 的 3×5 矩阵：v2 显式、v3 显式、v3 自动；必需窗缺失、歧义、失效绑定、有效目标、optional 缺失。比较 blocker/actions/target，断言 workspace scope、无全局收尾和零配置/状态/模拟桌面写入。安装测试同步检查缺失 portable 配置时拒绝旧的固定成功输出 |
| SW-05 / 已修复 | runtime 摘要必须对应实际未重写的源文件字节与修改后的 machine | confirm/activate/bindings/topology 保留 stableRead 的 source/config/machine/活动版本；所有 v3 编译调用必须显式提供 source。发现后、锁内写入前复核原代次；以预期新 machine 生成上下文。保存后验证 runtime 正文、元数据及 source/machine/version，写后不一致保留 guard。相邻 v2 bindings 也改用实际 source | `SW-05`：四个 producer × 紧凑/二空格/四空格/不同尾部换行，逐一通过 generationDocument、verifyRuntimeDocument 和正式 diagnostics 验证。四个 producer 分别覆盖发现期间源/机器/活动版本变化，写前拒绝不遗留 guard。activate 注入 runtime 写入失败、正文回读篡改、写后源变化，断言 guard 保留及 stableRead 拒绝 |

**旧实现失败证据：** 修改产品代码前，先向已有正式测试文件加入首批 23 个 `SW-*` 回归，通过 `node scripts/isolated-check.mjs node --test --test-name-pattern='SW-' configurator/test/review-remediation.test.mjs` 运行，结果 3 通过、20 失败，五项均有对应失败。v2 开/关和已正确的 v3 自动 workspace 入口作为通过对照。随后同批 23 项全部通过，再扩展失败、拓扑、并发及回读场景。不是将附录调查脚本的退出 0 当作修复证明。

**定向验证：** 首次扩展后的 56 项 `SW-*` 全部通过；另一次并发/不完整代次定向运行 18 项全部通过（含与前组重叠的 9 项 HTTP 并发检查）。最后增加的 9 项为拓扑并发、只读编译并发及写后失败。测试只加速 monitor 自身的采样定时器，不缩短发现/任务 deadline；所有服务退出并清理临时目录后才完成测试。

**最终验证：** 完整 `fish scripts/check.fish` 退出 0，内部通过 `scripts/isolated-check.mjs` 隔离运行；453 项 Node 测试全部通过（原 388 项 + 本次 65 项，0 失败/取消/跳过）。Fish 语法、JSON/schema、v1/v2/v3 fixtures、临时安装/卸载、本地发布归档/校验和/Homebrew 生成及 smoke 均通过，结尾为 `result=ok`、`OK SpaceWright release checks`。另行执行的 `fish -n bin/spacewright tests/install.fish`、修改的 Node 入口语法检查及最终 `git diff --check` 也通过。发布相关检查只生成临时本地样本，不代表已发布或升级安装。用户随后要求重新执行当前测试，完整检查再次退出 0，同样为 453 项 Node 测试全部通过，Fish fixtures、安装/卸载、发布包及 smoke 全部通过；本次只更新交付记录，不重复执行未变化的测试。

**剩余限制：** 未执行真实 yabai/displayplacer、应用激活、窗口/Spaces 变更、服务重启或 Sidecar；拓扑、任务执行和故障注入均使用临时配置与模拟后端。未安装升级或验证个人硬件的实际布局，不将本轮修复写成“所有用户故障均已解释”。原有普通保存、备份/历史恢复、取消、deadline、lease 回归已随最终完整检查通过；实际硬件与用户配置的实用观察仍未执行。

## 附录：修复前最小隔离调查（历史证据）

以下脚本仅保留修复前调查，修复后会因旧缺陷不再存在而改变结果；当前验收以第 6 节正式断言为准。下面代码是原审查使用的临时调查脚本；在仓库根目录将代码块保存到临时 `.mjs` 后，用 `node scripts/isolated-check.mjs node <临时脚本绝对路径>` 运行。它只创建临时配置和模拟后端，最后清理；不要在真实配置中直接运行各条缺陷命令。代码只观测已记录的错误，修复后应改成正确行为的正式断言；不要继续用调查退出码验收。

```javascript
import {mkdtemp,mkdir,writeFile,readFile,rm} from 'node:fs/promises';
import {existsSync} from 'node:fs';
import {join} from 'node:path';
import {tmpdir} from 'node:os';
import {spawn,execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {pathToFileURL} from 'node:url';
const repo=process.cwd(),imp=p=>import(pathToFileURL(join(repo,p))),exec=promisify(execFile);
const {starterConfig}=await imp('configurator/lib/config-v2.mjs');
const {starterV3}=await imp('configurator/lib/config-v3.mjs');
const {stableRead}=await imp('configurator/lib/config-store.mjs');
const root=await mkdtemp(join(tmpdir(),'spacewright-review-current-'));
let server;
try {
 const cfg=join(root,'config'),state=join(root,'state'),bin=join(root,'bin');await Promise.all([mkdir(cfg),mkdir(state),mkdir(bin)]);
 const source=JSON.stringify(starterConfig());await writeFile(join(cfg,'config.v2.json'),source);
 const env={...process.env,SPACEWRIGHT_CONFIG_ROOT:cfg,SPACEWRIGHT_STATE_ROOT:state,SPACEWRIGHT_BANNER_DISABLE:'1'};
 const dry=await exec(join(repo,'bin/spacewright'),['config-compile','--dry-run'],{env});
 console.log('COMPILE_DRY_RUN',JSON.stringify({runtimeWritten:existsSync(join(cfg,'generated/runtime.json')),stdout:dry.stdout.trim()}));
 await writeFile(join(cfg,'config.v2.json'),'{broken');
 let diffError;try{await exec(join(repo,'bin/spacewright'),['config-diff'],{env});}catch(e){diffError=e.stderr.trim();}
 await writeFile(join(cfg,'config.v2.json'),source);
 let readable;try{await stableRead(join(cfg,'config.v2.json'),join(state,'machine.json'));readable=true;}catch(e){readable=e.message;}
 console.log('DIFF_FAILURE',JSON.stringify({diffError,guardRemains:existsSync(join(cfg,'.configuration-write')),readAfterFix:readable}));
 await rm(join(cfg,'.configuration-write'),{recursive:true,force:true});
 await writeFile(join(bin,'yabai'),`#!/bin/sh\ncase "$3" in --displays) echo '[{"index":1,"uuid":"D","frame":{"x":0,"y":0,"w":1200,"h":900}}]';; --spaces) echo '[{"index":1,"uuid":"S","display":1,"label":"coding_solo","type":"float"}]';; *) echo '[]';; esac\n`,{mode:0o755});
 await writeFile(join(state,'machine.json'),JSON.stringify({displayBindings:{primary:'D'}}));
 const workEnv={...env,PATH:bin+':'+process.env.PATH};
 const preview=await exec(join(repo,'bin/spacewright'),['workspace','coding','solo','--dry-run'],{env:workEnv});
 let actual;try{await exec(join(repo,'bin/spacewright'),['apply','coding','solo','--dry-run','--json'],{env:workEnv});}catch(e){const v=JSON.parse(e.stdout);actual={exit:e.code,blockers:v.plan.blockers.map(b=>b.code)};}
 console.log('WORKSPACE_PREVIEW',JSON.stringify({exit:0,stdout:preview.stdout.trim(),realPlanner:actual}));
 const serverRoot=join(root,'server'),sc=join(serverRoot,'config'),ss=join(serverRoot,'state'),sb=join(serverRoot,'bin'),pkg=join(serverRoot,'package');await Promise.all([mkdir(sc,{recursive:true}),mkdir(ss,{recursive:true}),mkdir(sb,{recursive:true}),mkdir(join(pkg,'bin'),{recursive:true})]);
 const old=starterConfig();old.settings={...old.settings,eventAutomationEnabled:true};old.rules=[{id:'old_rule',enabled:true,when:{event:'wake'},then:{activateWorkspace:'coding',mode:'solo'}}];
 const active=starterV3();active.settings={...active.settings,eventAutomationEnabled:false};await writeFile(join(sc,'config.v2.json'),JSON.stringify(old));await writeFile(join(sc,'config.v3.json'),JSON.stringify(active));
 await writeFile(join(sb,'yabai'),`#!/bin/sh\ncase "$3" in\n--displays) echo '[{"index":1,"uuid":"D","frame":{"x":0,"y":0,"w":1200,"h":900},"is-built-in":true}]';;\n*) echo '[]';;\nesac\n`,{mode:0o755});
 await writeFile(join(pkg,'bin/spacewright'),`#!${process.execPath}\nrequire('fs').writeFileSync(${JSON.stringify(join(root,'legacy-dispatch'))},JSON.stringify(process.argv.slice(2)));console.log(JSON.stringify({noop:true}));\n`,{mode:0o755});
 server=spawn(process.execPath,[join(repo,'configurator/server.mjs'),`--config-root=${sc}`,`--state-root=${ss}`,`--package-root=${pkg}`,'--token=review-fixture','--port=0','--no-open'],{env:{...env,PATH:sb+':'+process.env.PATH},stdio:['ignore','pipe','pipe']});
 let errors='';server.stderr.on('data',d=>errors+=d);
 const url=await new Promise((resolve,reject)=>{let out='';const timer=setTimeout(()=>reject(Error('start timeout '+errors)),5000);server.stdout.on('data',d=>{out+=d;const m=out.match(/SPACEWRIGHT_CONFIGURATOR_URL=(http:\/\/[^?\s]+)/);if(m){clearTimeout(timer);resolve(m[1]);}});});
 process.kill(server.pid,'SIGUSR1');
 const end=Date.now()+5000;while(!existsSync(join(root,'legacy-dispatch'))&&Date.now()<end)await new Promise(r=>setTimeout(r,25));
 const tasks=await (await fetch(new URL('/api/tasks',url),{headers:{'x-spacewright-token':'review-fixture'},signal:AbortSignal.timeout(2000)})).json();
 console.log('V3_WAKE',JSON.stringify({activeAutomation:active.settings.eventAutomationEnabled,legacyAutomation:old.settings.eventAutomationEnabled,dispatched:await readFile(join(root,'legacy-dispatch'),'utf8').catch(()=>null),tasks:tasks.tasks.map(t=>({target:t.target,status:t.status}))}));
 await writeFile(join(ss,'machine.json'),JSON.stringify({version:2,hardwareProfile:'mac_mini',hardwareProfileConfirmed:true,displayBindings:{tall:'DISPLAY-TALL-1234'},topologySelections:{'external:tall':'single_tall'},activeSetup:'single_tall'}));
 await writeFile(join(sb,'sysctl'),'#!/bin/sh\necho Macmini9,1\n',{mode:0o755});
 await writeFile(join(sb,'yabai'),`#!/bin/sh\ncase "$3" in --displays) echo '[{"index":1,"uuid":"DISPLAY-TALL-1234","frame":{"x":0,"y":0,"w":1200,"h":1920},"is-built-in":false}]';; *) echo '[]';; esac\n`,{mode:0o755});
 const activated=await fetch(new URL('/api/v3/setup/activate',url),{method:'POST',headers:{'x-spacewright-token':'review-fixture','content-type':'application/json'},body:'{}',signal:AbortSignal.timeout(5000)});
 const activationBody=await activated.json();
 const savedSource=await readFile(join(sc,'config.v3.json'),'utf8');
 const compiled=JSON.parse(await readFile(join(sc,'generated/runtime.json'),'utf8'));
 const {hash}=await imp('configurator/lib/config-store.mjs');
 console.log('ACTIVATION_SOURCE',JSON.stringify({http:activated.status,activated:activationBody.activated,sourceUnchanged:savedSource===JSON.stringify(active),actualSourceHash:hash(savedSource),compiledSourceHash:compiled.generated.source_sha256,matches:hash(savedSource)===compiled.generated.source_sha256}));

}finally{if(server){const exit=new Promise(r=>server.once('exit',r));server.kill('SIGTERM');await Promise.race([exit,new Promise(r=>setTimeout(r,3000))]);if(server.exitCode===null)server.kill('SIGKILL');}await rm(root,{recursive:true,force:true});}
```

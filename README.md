# Workspace 用户指南

这个目录维护 macOS workspace 自动化系统。它通过 `fish` 函数调用
`yabai`、`displayplacer` 和 `skhd`，把常用工作场景整理成稳定入口。

当前系统分为四个主要模块：

- `coding`
- `research`
- `office`
- `gtd`

本文件面向日常使用和排查。更底层的设计规则、边界和后续路线记录在
`design-notes.md`。

## 安全边界

只读命令不会移动窗口、创建或删除 Space，也不会切换显示器配置：

```fish
work_inventory
work_doctor
work_smoke
work_audit
work_status
work_mode_status
work_diagnostics
work_display_health
workspace_snapshot
workspace_plan gtd_meeting_wide
workspace_verify gtd_meeting_wide
```

会改变窗口或 Space 状态的命令包括：

```fish
work_solo
work_wide
work_tall
coding_solo
coding_wide
coding_tall
research_solo
research_wide
research_tall
office_wide
office_tall
gtd_solo_all
gtd_wide
gtd_tall
gtd_ai
gtd_ai_solo
gtd_ai_wide
gtd_ai_tall
gtd_chat
gtd_calendar
workspace_cleanup_known_labeled_spaces
cleanup_unlabeled_empty_spaces
work_recover_light
```

会改变显示器布局的命令包括：

```fish
display_apply_solo
display_apply_wide_left
display_apply_tall_left
```

维护代码时，默认先运行只读检查。只有在明确希望调整当前桌面状态时，才运行
`display_apply_*`、`work_*` 或模块入口。

## 第一次配置

新机器、重装 macOS 或 yabai/displayplacer 重置后，先设置 workspace primary
display。它是固定工作区的位置，例如 `gtd_chat`、`gtd_calendar` 和
`coding_control`。

推荐流程：

```fish
work_reload
detect_and_set_workspace_primary_display_uuid
get_workspace_primary_display_uuid
work_diagnostics
```

如果自动检测失败，先查看 display 信息：

```fish
ws_query_displays bootstrap display-list | ws_jq -r '.[] | "index=\(.index) uuid=\(.uuid) focus=\(.[\"has-focus\"]) frame=(\(.frame.x),\(.frame.y),\(.frame.w),\(.frame.h)) spaces=\(.spaces)"'
```

然后手动设置：

```fish
set_workspace_primary_display_uuid <display-uuid>
get_workspace_primary_display_uuid
```

该值保存在 fish universal variable `WORKSPACE_PRIMARY_DISPLAY_UUID` 中。

## 三种显示模式

| 模式 | 显示器动作 | workspace 动作 | 用途 |
|---|---|---|---|
| Solo | `display_apply_solo` | `work_solo` | 只使用 workspace primary display |
| Wide | `display_apply_wide_left` | `work_wide` | 左侧横向外接屏作为主要任务显示器 |
| Tall | `display_apply_tall_left` | `work_tall` | 左侧纵向外接屏作为主要任务显示器 |

常用组合：

```fish
display_apply_solo
work_solo

display_apply_wide_left
work_wide

display_apply_tall_left
work_tall
```

`display_apply_*` 只负责显示器几何和显示健康检查；`work_*` 负责进入工作场景。
`skhd` 快捷键里使用 `display_apply_*; work_*`，所以即使显示健康检查给出 warning，
仍会继续尝试进入 workspace 模式。

## 顶层工作模式

| 命令 | 包含内容 |
|---|---|
| `work_solo` | `coding_solo`、`research_solo`、`gtd_solo_all` |
| `work_wide` | `coding_wide`、`research_wide`、`office_wide`、`gtd_wide`、`gtd_chat`、`gtd_calendar`、`coding_control` |
| `work_tall` | `coding_tall`、`research_tall`、`office_tall`、`gtd_tall`、`gtd_chat`、`gtd_calendar`、`coding_control` |

顶层入口保持公开命令稳定，方便 shell、`skhd` 和肌肉记忆继续使用。

## 模块入口

### Coding

| 命令 | 作用 |
|---|---|
| `coding_solo` | 内置/主显示器上的 VS Code 单独工作区 |
| `coding_wide` | wide 外接屏：ChatGPT 左侧 1/3，VS Code 右侧 2/3 |
| `coding_tall` | tall 外接屏：ChatGPT 上半，VS Code 下半 |
| `coding_control` | primary display 上的 Warp、SmartGit、KeePassXC、FlClash/Thaw 控制区 |

`coding_editor_wide` 和 `coding_editor_tall` 只收集已经打开的 ChatGPT 窗口，不会自动启动
ChatGPT。ChatGPT 不存在时，VS Code 使用整个 workspace；`coding_editor_solo` 仍保持 VS Code 全屏。

### Research

| 命令 | 作用 |
|---|---|
| `research_solo` | Zotero + ChatGPT，主显示器 |
| `research_wide` | Zotero + Claude，wide 外接屏 |
| `research_tall` | Zotero + Claude，tall 外接屏 |

### Office

| 命令 | 作用 |
|---|---|
| `office_writing_wide` | Word + ChatGPT，wide 外接屏 |
| `office_writing_tall` | Word + ChatGPT，tall 外接屏 |
| `office_slides_wide` | PowerPoint + ChatGPT，wide 外接屏 |
| `office_slides_tall` | PowerPoint + ChatGPT，tall 外接屏 |
| `office_wide` | writing + slides 的 wide 聚合入口 |
| `office_tall` | writing + slides 的 tall 聚合入口 |

Office 入口在主应用没有可用窗口时会尽量保持 no-op，不主动制造空工作区。Word
和 PowerPoint 会收集所有可移动窗口；ChatGPT 是共享辅助窗口，存在时一起进入
对应 Office workspace。

Wide 布局：ChatGPT 占左三分之一；一个 Word/PowerPoint 窗口占右侧三分之二；
两个文档窗口分别占中、右三分之一；三个或更多文档窗口时，第一个占中间三分之一，
第二、第三个分占右侧上下半区。

Tall 布局：一个文档窗口时，ChatGPT 占上半屏，文档占下半屏；两个文档窗口时，
ChatGPT 占左上，第一个文档占右上，第二个文档占下半屏；三个或更多文档窗口时，
下半屏左右分给第二、第三个文档窗口。

### GTD

| 命令 | 作用 |
|---|---|
| `gtd_support_solo` / `gtd_support_wide` / `gtd_support_tall` | Dia 支撑工作区 |
| `gtd_review_solo` / `gtd_review_wide` / `gtd_review_tall` | Finder、Preview、Notes、ChatGPT 的 review 工作区 |
| `gtd_mail_solo` / `gtd_mail_wide` / `gtd_mail_tall` | Thunderbird、Outlook 邮件工作区 |
| `gtd_meeting_solo` / `gtd_meeting_wide` / `gtd_meeting_tall` | Zoom、Teams 会议工作区 |
| `gtd_ai` / `gtd_ai_solo` / `gtd_ai_wide` / `gtd_ai_tall` | ChatGPT、Obsidian、Notes 的 AI 工作区 |
| `gtd_chat` | primary display 上的聊天工作区 |
| `gtd_calendar` | primary display 上的 Calendar + Reminders |
| `gtd_solo_all` | solo 模式下的 GTD 聚合入口 |
| `gtd_wide` | wide 模式下的 GTD 聚合入口 |
| `gtd_tall` | tall 模式下的 GTD 聚合入口 |

GTD 模块包含最多 app-specific 规则。Outlook、Zoom、Teams、Dia、Preview、
Notes、Thunderbird、DingTalk 等特殊行为仍保留在 fish helper 中，不由通用配置层接管。Mail
workspace 以 Thunderbird 为必需主窗口，Outlook 存在时作为辅助窗口进入同一
workspace；wide 左右分，tall 上下分。

#### GTD AI Workspace

Shortcut: `9`

Apps: ChatGPT, Obsidian, Notes.

Entrypoints:

```fish
gtd_ai
gtd_ai_wide
gtd_ai_tall
gtd_ai_solo
```

`gtd_ai` detects the current display mode and dispatches to the matching mode
entry. The explicit skhd bindings use the same mode-specific pattern as the
other numbered workspaces.

Wide layout: Notes left third, Obsidian middle third, ChatGPT right third.

Tall layout: Notes top-left, Obsidian top-right, ChatGPT bottom half.

Solo layout: Notes top-left, Obsidian top-right, ChatGPT bottom half.

`gtd_ai` is not part of the aggregate `work_*` entries because it opens missing
apps when invoked directly.

## 快捷键

快捷键由 `.config/skhd/skhdrc` 提供。完整表格见：

```text
.config/skhd/README.md
```

核心规律：

| 修饰键 | 模式 |
|---|---|
| `Fn + Shift + 数字` | Solo |
| `Option + Shift + 数字` | Wide |
| `Control + Shift + 数字` | Tall |

数字映射：

| 数字 | workspace family |
|---|---|
| `0` | `work` |
| `1` | `coding` |
| `2` | `research` |
| `3` | `gtd_support` |
| `4` | `gtd_review` |
| `5` | `gtd_mail` |
| `6` | `gtd_meeting` |
| `7` | `office_writing` |
| `8` | `office_slides` |
| `9` | `gtd_ai` |

## 日常检查

修改 workspace 代码后，推荐先运行：

```fish
work_reload
work_smoke
work_doctor
```

常用只读检查：

| 命令 | 用途 |
|---|---|
| `work_inventory` | 打印当前 workspace 声明清单、模块、display entry、helper 和依赖 |
| `work_command_check` | 检查公开命令和 helper 是否已加载 |
| `work_smoke` | 检查 reload、command check、audit 和所有 dry-run 入口 |
| `work_audit` | 检查 mode symmetry、ownership policy、helper coverage 和空 label 状态 |
| `work_doctor` | 检查依赖、fish syntax、reload、只读 yabai query、display health 和 bad-window cache |
| `work_diagnostics` | 查看 display、labeled spaces、duplicate labels、empty spaces 和 bad-window cache |
| `work_display_health [mode]` | 检查 primary/target display、外接屏位置、形状和 Dock 设置 |
| `workspace_snapshot` | 一次查询并输出当前 displays、Spaces 和 windows JSON |
| `workspace_plan [--json] <workspace>` | 基于当前快照显示窗口匹配、目标 Space、fallback 候选和计划布局 |
| `workspace_verify [--json] <workspace>` | 检查当前窗口归属、label、display 和布局是否符合 workspace 契约 |
| `workspace_verify [--json] --all` | 使用同一次快照汇总所有已配置观测契约的 `satisfied`、`drift` 和 `not_applicable` 状态 |
| `workspace_restore_labels [--json] [--dry-run] [workspace ...]` | 只读规划可安全恢复的缺失 label；不传 workspace 时检查全部观测契约 |
| `work_smoke_observability` | 定向检查 snapshot、verify 汇总和 label-only 恢复安全边界 |

`work_inventory`、`work_command_check`、`work_smoke` 的核心命令清单来自
`common/workspace_manifest.fish`。这是一层只读 manifest：它统一文档和检查事实，
但不会移动窗口，也不替代模块运行逻辑。

## Plan 与 Verify

当前只读观测层覆盖 `gtd_meeting_wide` 和 `coding_control`：

```fish
workspace_plan gtd_meeting_wide
workspace_verify gtd_meeting_wide

workspace_plan --json coding_control
workspace_verify --json coding_control

workspace_verify --all
```

`workspace_plan` 使用一次 display、Space 和 window 快照说明当前会匹配哪些窗口、
目标 display/Space、可能的 fallback，以及预期布局。`workspace_verify` 使用同一种快照
检查当前结果，发现窗口仍在其他 Space、label 重复、混入无关窗口或布局不符时返回非零。

这些命令和 `workspace_snapshot` 都不会激活或打开应用、重启 yabai、移动窗口、
创建或删除 Space、运行 cleanup，也不会应用 display profile。

## Label-only 恢复

如果窗口位置和布局正确，但 yabai label 在 Dock/yabai 重启后丢失，先查看恢复计划：

```fish
workspace_restore_labels
workspace_restore_labels --json gtd_meeting_wide coding_control
```

默认行为等同于 `--dry-run`。只有同时满足以下条件时，结果才会是 `ready`：

- workspace 窗口只指向一个候选 Space
- 候选 Space 位于契约要求的 display
- 候选 Space 没有其他 label
- 候选 Space 没有不属于该 workspace 的非最小化窗口
- 当前不存在同名 label 或重复 label

确认计划后，显式应用：

```fish
workspace_restore_labels --apply gtd_meeting_wide coding_control
```

`--apply` 只执行 yabai `space --label`，不会移动窗口、切换 Space、创建或删除 Space、
运行 cleanup 或应用 display profile。如果任一请求的 workspace 返回 `blocked_*`，整次
应用会在写入前停止，避免只恢复一部分 label。

## Dry Run

大多数入口支持 `--dry-run`：

```fish
work_wide --dry-run
coding_tall --dry-run
gtd_meeting_wide --dry-run
```

Dry-run 只打印声明信息，不查询 yabai、不创建 Space、不移动窗口、不切换 display。

## 故障排查流程

如果布局结果不符合预期，先不要重复运行会移动窗口的入口。推荐顺序：

```fish
work_reload
work_diagnostics
work_display_health
work_bad_windows --summary
work_audit
```

如果 yabai query 明显卡住或失败：

```fish
yabai --restart-service
work_reload
work_diagnostics
```

如果出现很多空 Space，可以先看状态：

```fish
work_mode_status
work_diagnostics
```

确认只想清理空 Space 时，再运行：

```fish
work_recover_light
```

`work_recover_light` 会运行 diagnostics、清理空的 known-labeled Spaces 和空的
unlabeled Spaces，再运行 diagnostics。它不会移动已有窗口，也不会应用 display profile。

## 维护约定

- 公开命令名保持稳定：`work_wide`、`coding_tall`、`gtd_meeting_wide` 等不随内部实现随意改名。
- 业务层 workspace 不硬编码 display UUID，应通过 `resolve_workspace_primary_display` 和 `resolve_workspace_external_display`。
- app 名称匹配优先走 `workspace_app_name`、`workspace_app_names`、`workspace_app_regex` 和 app-key selector。
- labeled Space 使用 `find_or_create_labeled_space`、`prepare_labeled_space` 和 `workspace_prepare_labeled_space`。
- GTD 的复杂窗口选择和恢复逻辑保留模块本地实现，只有稳定重复事实进入 manifest。
- display profile 只负责显示器布局；workspace entry 负责进入工作流。
- 普通维护优先运行只读检查，不默认运行会改变桌面状态的命令。

## 相关文件

| 文件 | 作用 |
|---|---|
| `common/workspace_manifest.fish` | 只读 workspace 声明清单 |
| `common/workspace_observability.fish` | workspace snapshot、plan 和 verify |
| `common/workspace_label_recovery.fish` | 显式、默认只读的 label-only 恢复 |
| `common/work_smoke_observability.fish` | observability 和 label 恢复的定向 smoke |
| `common/work_entries.fish` | `work_solo`、`work_wide`、`work_tall` |
| `common/source_workspace_common.fish` | 公共 helper 加载入口 |
| `common/workspace_module_reloads.fish` | 模块 reload 定义 |
| `common/work_inventory.fish` | workspace 清单输出 |
| `common/work_command_check.fish` | 命令加载检查 |
| `common/work_smoke.fish` | regression smoke checks |
| `common/work_audit.fish` | architecture drift audit |
| `display/display_entries.fish` | display profile 入口 |
| `coding/`、`research/`、`office/`、`gtd/` | 模块入口和模块本地 helper |
| `design-notes.md` | 维护者设计说明和路线图 |

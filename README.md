# Workspace Commands

本目录主要管理基于 `fish + yabai + skhd` 的工作空间切换、布局恢复与状态检查。

## 常用命令速查

### 1. 总入口命令

| 命令 | 作用 | 典型使用场景 |
|---|---|---|
| `work_wide` | 切换到整体 wide 工作模式 | 外接屏横向布局工作时使用 |
| `work_tall` | 切换到整体 tall 工作模式 | 外接屏纵向布局工作时使用 |
| `work_status` | 查看当前整体 workspace 状态 | 排查当前空间分布是否正常 |
| `work_mode_status` | 查看各模块当前 mode 状态 | 检查 GTD / Coding / Office / Research 当前布局情况 |
| `work_reload` | 重新加载 workspace 相关 fish functions | 修改 workspace 脚本后使用 |

---

### 2. GTD 模块

| 命令 | 作用 | 典型使用场景 |
|---|---|---|
| `gtd_wide_all` | 进入 GTD wide 总模式，同时加载 internal 区域 | 进入 GTD 日常工作宽屏模式 |
| `gtd_tall_all` | 进入 GTD tall 总模式，同时加载 internal 区域 | 进入 GTD 日常工作竖屏模式 |
| `gtd_wide` | 仅执行 GTD 外接屏 wide 布局 | 单独调整 GTD 外接屏布局时 |
| `gtd_tall` | 仅执行 GTD 外接屏 tall 布局 | 单独调整 GTD 外接屏布局时 |
| `gtd_chat` | 打开或恢复 GTD 聊天区 | 处理微信、消息、Keybase、钉钉时 |
| `gtd_calendar` | 打开或恢复 GTD 日历区 | 查看 Calendar 与 Reminders 时 |
| `gtd_mail_wide` | GTD 邮件区 wide 布局 | Thunderbird 邮件处理 |
| `gtd_mail_tall` | GTD 邮件区 tall 布局 | Thunderbird 邮件处理 |
| `gtd_meeting_wide` | GTD 会议区 wide 布局 | Outlook、Zoom、Teams 会议场景 |
| `gtd_meeting_tall` | GTD 会议区 tall 布局 | Outlook、Zoom、Teams 会议场景 |
| `gtd_support_wide` | GTD 支撑区 wide 布局 | Dia、Notes 等辅助工作 |
| `gtd_support_tall` | GTD 支撑区 tall 布局 | Dia、Notes 等辅助工作 |
| `gtd_review_wide` | GTD 评审区 wide 布局 | Finder + Preview + ChatGPT + Notes 的论文评审场景 |
| `gtd_review_tall` | GTD 评审区 tall 布局 | Finder + Preview + ChatGPT + Notes 的论文评审场景 |
| `gtd_status` | 查看 GTD 详细状态 | 检查 GTD spaces、displays、apps |
| `gtd_mode_status` | 查看 GTD mode 状态 | 检查 GTD wide / tall / internal spaces |
| `gtd_reload` | 重新加载 GTD 相关 fish functions | 修改 GTD 脚本后使用 |

---

### 3. Coding 模块

| 命令 | 作用 | 典型使用场景 |
|---|---|---|
| `coding_wide_all` | 进入 Coding wide 总模式，并加载 control 区 | 编码主工作流，宽屏模式 |
| `coding_tall_all` | 进入 Coding tall 总模式，并加载 control 区 | 编码主工作流，竖屏模式 |
| `coding_wide` | 仅执行 Coding 外接屏 wide 布局 | 单独调整 coding editor 区时 |
| `coding_tall` | 仅执行 Coding 外接屏 tall 布局 | 单独调整 coding editor 区时 |
| `coding_editor_wide` | Coding editor 的 wide 布局 | 左 ChatGPT，右 VS Code |
| `coding_editor_tall` | Coding editor 的 tall 布局 | 上 ChatGPT，下 VS Code |
| `coding_control` | 打开或恢复 Coding internal 控制区 | Warp + SmartGit 辅助区 |
| `coding_status` | 查看 Coding 详细状态 | 检查 Coding spaces 和 apps |
| `coding_mode_status` | 查看 Coding mode 状态 | 检查 Coding wide / tall / internal spaces |
| `coding_reload` | 重新加载 Coding 相关 fish functions | 修改 Coding 脚本后使用 |

---

### 4. Office 模块

| 命令 | 作用 | 典型使用场景 |
|---|---|---|
| `office_wide` | 进入 Office wide 模式 | 文字与幻灯片工作场景 |
| `office_tall` | 进入 Office tall 模式 | 文字与幻灯片工作场景 |
| `office_writing_wide` | Office 写作区 wide 布局 | Word 写作 |
| `office_writing_tall` | Office 写作区 tall 布局 | Word 写作 |
| `office_slides_wide` | Office 幻灯片区 wide 布局 | PowerPoint 制作 |
| `office_slides_tall` | Office 幻灯片区 tall 布局 | PowerPoint 制作 |
| `office_status` | 查看 Office 详细状态 | 检查 Office spaces 和 apps |
| `office_mode_status` | 查看 Office mode 状态 | 检查 Office wide / tall spaces |
| `office_reload` | 重新加载 Office 相关 fish functions | 修改 Office 脚本后使用 |

---

### 5. Research 模块

| 命令 | 作用 | 典型使用场景 |
|---|---|---|
| `research_wide` | 进入 Research wide 模式 | Zotero 研究工作场景 |
| `research_tall` | 进入 Research tall 模式 | Zotero 研究工作场景 |
| `research_status` | 查看 Research 详细状态 | 检查 Research spaces 和 apps |
| `research_mode_status` | 查看 Research mode 状态 | 检查 Research wide / tall spaces |
| `research_reload` | 重新加载 Research 相关 fish functions | 修改 Research 脚本后使用 |

---

### 6. Cleanup 命令

| 命令 | 作用 | 典型使用场景 |
|---|---|---|
| `gtd_cleanup_wide_spaces` | 清理空的 GTD wide spaces | wide space 遗留时 |
| `gtd_cleanup_tall_spaces` | 清理空的 GTD tall spaces | tall space 遗留时 |
| `coding_cleanup_wide_spaces` | 清理空的 Coding wide spaces | coding wide 遗留时 |
| `coding_cleanup_tall_spaces` | 清理空的 Coding tall spaces | coding tall 遗留时 |
| `office_cleanup_wide_spaces` | 清理空的 Office wide spaces | office wide 遗留时 |
| `office_cleanup_tall_spaces` | 清理空的 Office tall spaces | office tall 遗留时 |
| `research_cleanup_wide_spaces` | 清理空的 Research wide spaces | research wide 遗留时 |
| `research_cleanup_tall_spaces` | 清理空的 Research tall spaces | research tall 遗留时 |

---

## 推荐使用顺序

| 场景 | 推荐命令 |
|---|---|
| 整体切到宽屏工作流 | `work_wide` |
| 整体切到竖屏工作流 | `work_tall` |
| 进入 GTD 日常工作流 | `gtd_wide_all` / `gtd_tall_all` |
| 进入论文评审工作流 | `gtd_review_wide` / `gtd_review_tall` |
| 进入编码工作流 | `coding_wide_all` / `coding_tall_all` |
| 检查当前系统状态 | `work_status` |
| 检查当前模块布局状态 | `work_mode_status` |

---

## 当前设计约定

| 类型 | 约定 |
|---|---|
| internal spaces | 常驻、复用型空间，例如 `gtd_chat`、`gtd_calendar`、`coding_control` |
| external spaces | 按需创建的专项工作区，通常要求核心 app 已打开 |
| wide / tall | 表示外接屏的两种主要布局模式 |
| `*_all` | 组合入口，通常同时处理 external 与 internal 区域 |
| `*_status` | 查看详细状态 |
| `*_mode_status` | 查看模块级别布局状态 |
| `*_reload` | 修改 fish functions 后重新加载 |

---

## 备注

- `skhd` 当前主要绑定的是高频入口命令，例如 `work_wide`、`work_tall`、`gtd_review_wide`、`coding_wide_all`。
- `yabai` 负责底层的 space、window、display 管理。
- `fish functions` 负责具体业务逻辑。
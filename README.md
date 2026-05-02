# Workspace

This directory manages the workspace automation layer built on top of:

- fish functions
- yabai
- skhd

The workspace subsystem is responsible for organizing repeatable work modes, app layouts, and task-oriented workspaces across the internal and external displays.

## What This Directory Is For

The workspace layer provides:

- wide and tall work modes
- GTD workspaces
- coding workspaces
- office workspaces
- research workspaces
- internal fixed spaces and external task spaces
- status and reload commands for daily use and debugging

This `README.md` focuses on how to use the commands.

For design rationale and architecture decisions, see:

- [design-notes.md](design-notes.md)

## Command Structure

The command naming follows a consistent structure.

| Type | Meaning |
|---|---|
| `*_wide` | apply the wide layout for a module or workspace |
| `*_tall` | apply the tall layout for a module or workspace |
| `*_all` | full entry point for a module, usually including related internal spaces and cleanup |
| `*_status` | show detailed current state |
| `*_mode_status` | show current mode-level status |
| `*_reload` | reload fish functions after editing scripts |

## Most Common Commands

### Global entry points

| Command | Purpose | Typical use |
|---|---|---|
| `work_wide` | switch the whole system into wide work mode | normal external-display wide workflow |
| `work_tall` | switch the whole system into tall work mode | normal external-display tall workflow |
| `work_status` | show the overall current workspace state | troubleshooting or verification |
| `work_mode_status` | show mode status across modules | checking GTD / Coding / Office / Research layouts |
| `work_reload` | reload workspace-related fish functions | after editing workspace scripts |

## GTD Commands

### Main GTD entry points

| Command | Purpose | Typical use |
|---|---|---|
| `gtd_wide_all` | enter the full GTD wide mode | GTD daily work on wide layout |
| `gtd_tall_all` | enter the full GTD tall mode | GTD daily work on tall layout |
| `gtd_wide` | apply only the GTD external wide layout | adjusting GTD external spaces only |
| `gtd_tall` | apply only the GTD external tall layout | adjusting GTD external spaces only |

### GTD internal spaces

| Command | Purpose | Typical use |
|---|---|---|
| `gtd_chat` | restore or open the GTD chat space | Keybase, WeChat, DingTalk, Messages |
| `gtd_calendar` | restore or open the GTD calendar space | Calendar and Reminders |

### GTD task spaces

| Command | Purpose | Typical use |
|---|---|---|
| `gtd_mail_wide` | GTD mail workspace in wide layout | Thunderbird mail handling |
| `gtd_mail_tall` | GTD mail workspace in tall layout | Thunderbird mail handling |
| `gtd_meeting_wide` | GTD meeting workspace in wide layout | Outlook, Zoom, Teams on wide layout |
| `gtd_meeting_tall` | GTD meeting workspace in tall layout | Outlook, Zoom, Teams on tall layout |
| `gtd_support_wide` | GTD support workspace in wide layout | Dia and Notes support work |
| `gtd_support_tall` | GTD support workspace in tall layout | Dia and Notes support work |
| `gtd_review_wide` | GTD review workspace in wide layout | Finder, Preview, ChatGPT, Notes for review |
| `gtd_review_tall` | GTD review workspace in tall layout | Finder, Preview, ChatGPT, Notes for review |

### GTD status and reload

| Command | Purpose |
|---|---|
| `gtd_status` | show detailed GTD state |
| `gtd_mode_status` | show GTD wide / tall / internal mode state |
| `gtd_reload` | reload GTD-related fish functions |

## Coding Commands

### Main Coding entry points

| Command | Purpose | Typical use |
|---|---|---|
| `coding_wide_all` | enter the full Coding wide mode | normal coding workflow on wide layout |
| `coding_tall_all` | enter the full Coding tall mode | normal coding workflow on tall layout |
| `coding_wide` | apply only the Coding external wide layout | adjusting coding editor workspace only |
| `coding_tall` | apply only the Coding external tall layout | adjusting coding editor workspace only |

### Coding task spaces

| Command | Purpose | Typical use |
|---|---|---|
| `coding_editor_wide` | coding editor workspace in wide layout | left ChatGPT, right VS Code |
| `coding_editor_tall` | coding editor workspace in tall layout | top ChatGPT, bottom VS Code |
| `coding_control` | internal coding support workspace | Warp and SmartGit |

### Coding status and reload

| Command | Purpose |
|---|---|
| `coding_status` | show detailed Coding state |
| `coding_mode_status` | show Coding wide / tall / internal mode state |
| `coding_reload` | reload Coding-related fish functions |

## Office Commands

| Command | Purpose | Typical use |
|---|---|---|
| `office_wide` | enter Office wide mode | writing and slides work on wide layout |
| `office_tall` | enter Office tall mode | writing and slides work on tall layout |
| `office_writing_wide` | Office writing workspace in wide layout | Microsoft Word |
| `office_writing_tall` | Office writing workspace in tall layout | Microsoft Word |
| `office_slides_wide` | Office slides workspace in wide layout | Microsoft PowerPoint |
| `office_slides_tall` | Office slides workspace in tall layout | Microsoft PowerPoint |
| `office_status` | show detailed Office state | troubleshooting |
| `office_mode_status` | show Office mode state | checking wide / tall spaces |
| `office_reload` | reload Office-related fish functions | after editing Office scripts |

## Research Commands

| Command | Purpose | Typical use |
|---|---|---|
| `research_wide` | enter Research wide mode | Zotero research workflow on wide layout |
| `research_tall` | enter Research tall mode | Zotero research workflow on tall layout |
| `research_status` | show detailed Research state | troubleshooting |
| `research_mode_status` | show Research mode state | checking wide / tall spaces |
| `research_reload` | reload Research-related fish functions | after editing Research scripts |

## Cleanup Commands

These are usually not the first commands you run manually, but they are useful when checking or maintaining the system.

| Command | Purpose |
|---|---|
| `gtd_cleanup_wide_spaces` | remove empty GTD wide spaces |
| `gtd_cleanup_tall_spaces` | remove empty GTD tall spaces |
| `coding_cleanup_wide_spaces` | remove empty Coding wide spaces |
| `coding_cleanup_tall_spaces` | remove empty Coding tall spaces |
| `office_cleanup_wide_spaces` | remove empty Office wide spaces |
| `office_cleanup_tall_spaces` | remove empty Office tall spaces |
| `research_cleanup_wide_spaces` | remove empty Research wide spaces |
| `research_cleanup_tall_spaces` | remove empty Research tall spaces |

## Recommended Usage Patterns

### Start a normal working session

| Goal | Recommended command |
|---|---|
| start the whole system in wide mode | `work_wide` |
| start the whole system in tall mode | `work_tall` |

### Enter a focused workflow directly

| Goal | Recommended command |
|---|---|
| enter review mode | `gtd_review_wide` or `gtd_review_tall` |
| enter coding mode | `coding_wide_all` or `coding_tall_all` |
| enter GTD meeting mode | `gtd_meeting_wide` or `gtd_meeting_tall` |
| enter GTD support mode | `gtd_support_wide` or `gtd_support_tall` |

### Inspect current state

| Goal | Recommended command |
|---|---|
| check overall status | `work_status` |
| check overall mode state | `work_mode_status` |
| check GTD state | `gtd_mode_status` |
| check Coding state | `coding_mode_status` |

## Current Design Conventions

| Concept | Meaning |
|---|---|
| internal spaces | persistent reusable support spaces such as `gtd_chat`, `gtd_calendar`, `coding_control` |
| external spaces | task-oriented spaces created on demand |
| wide / tall | the two main external-display layout modes |
| `*_all` | full module entry points, usually including related internal spaces and cleanup |
| status commands | used to inspect current system state |
| reload commands | used after changing fish scripts |

## Important Notes

### Internal vs external spaces

Internal spaces are intended to be more persistent and reusable.

Examples:

- `gtd_chat`
- `gtd_calendar`
- `coding_control`

External task spaces are more conditional and usually depend on a core app being open.

Examples:

- `gtd_mail_*`
- `gtd_review_*`
- `coding_editor_*`
- `office_*`
- `research_*`

### Core-app creation rule

Many external spaces are only created if the related core application exists.

Examples:

- GTD mail requires `Thunderbird`
- GTD review requires `Preview`
- Coding editor requires `Code`
- Office writing requires `Microsoft Word`
- Office slides requires `Microsoft PowerPoint`
- Research requires `Zotero`

### Hotkey layer

Many of the most frequently used commands are also bound through `skhd`.

See:

- [../.config/skhd/README.md](../.config/skhd/README.md)
- [../.config/skhd/design-notes.md](../.config/skhd/design-notes.md)

## Related Documentation

| Document | Purpose |
|---|---|
| [design-notes.md](design-notes.md) | workspace design and architecture notes |
| [../.config/skhd/README.md](../.config/skhd/README.md) | skhd hotkey usage |
| [../.config/skhd/design-notes.md](../.config/skhd/design-notes.md) | skhd design notes |
| [../.config/yabai/design-notes.md](../.config/yabai/design-notes.md) | yabai design notes |
| [../migration-notes.md](../migration-notes.md) | migration workflow for a new machine |

## Practical Advice

A good default approach is:

1. use `work_wide` or `work_tall` for broad mode switching
2. use direct module commands when entering a very specific task state
3. use `*_status` or `*_mode_status` when something looks wrong
4. use `*_reload` after editing workspace fish scripts

This keeps the system predictable and easy to recover when needed.
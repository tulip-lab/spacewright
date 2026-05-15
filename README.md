# Workspace System

## Overview

This workspace system is organized into four operational modules:

- `gtd`
- `coding`
- `office`
- `research`

Each module follows a consistent structure wherever applicable:

- cleanup helpers
- reload function
- status helpers
- mode-status helper
- `tall` entry
- `wide` entry
- optional `internal` workspaces for module-specific fixed layouts

The system is designed to keep workspace behavior predictable, composable, and portable across machines.

## New Machine Bootstrap

On a new Mac or after a macOS/yabai reset, configure the internal display UUID before relying on WIDE, TALL, or internal workspace commands.

Recommended bootstrap:

```fish
work_reload
detect_and_set_internal_display_uuid
get_internal_display_uuid
work_diagnostics
```

`detect_and_set_internal_display_uuid` uses `yabai` display metadata as the source of truth. It is safe when the topology is simple enough to infer the internal display. If it cannot determine the internal display confidently, inspect the current displays:

```fish
yabai -m query --displays | jq -r '.[] | "index=\(.index) uuid=\(.uuid) focus=\(.[\"has-focus\"]) frame=(\(.frame.x),\(.frame.y),\(.frame.w),\(.frame.h)) spaces=\(.spaces)"'
```

Then set the internal display manually:

```fish
set_internal_display_uuid <internal-display-uuid>
```

Confirm the stored value:

```fish
get_internal_display_uuid
```

The value is stored in the fish universal variable `WORKSPACE_INTERNAL_DISPLAY_UUID`, so it persists across future fish sessions for the same user.

This setup matters because internal fixed workspaces such as `gtd_chat`, `gtd_calendar`, and `coding_control` must stay anchored to the internal display. External modes such as `work_wide` and `work_tall` also use the configured internal UUID to identify the external display.

## Common Helper Layer

Shared helpers are located in `workspace/common`.

They are responsible for:

- creating or reusing labeled spaces
- normalizing labeled spaces
- resolving target displays
- focusing displays and spaces safely
- cleaning unlabeled empty spaces
- resolving internal and external display roles
- storing and reading the configured internal display UUID
- best-effort detection of the internal display UUID

Current core helpers include:

- `find_or_create_labeled_space`
- `prepare_labeled_space`
- `source_workspace_common`
- `workspace_status_snapshot`
- `workspace_mode_status_section`
- `cleanup_unlabeled_empty_spaces`
- `resolve_target_display`
- `resolve_internal_display`
- `resolve_external_display`
- `ws_focus_display`
- `ws_focus_space`
- `set_internal_display_uuid`
- `get_internal_display_uuid`
- `detect_and_set_internal_display_uuid`
- `work_diagnostics`
- `work_bad_windows`
- `work_clear_bad_windows`
- `work_cleanup_empty_labeled_spaces`
- `work_cleanup_empty_unlabeled_spaces`
- `work_recover_light`
- `work_command_check`

These helpers allow all module-level workspace functions to share the same lifecycle and display-selection logic.

## Diagnostics And Light Recovery

Use `work_diagnostics` first when a display transition or workspace command leaves the system in an unexpected state:

```fish
work_reload
work_diagnostics
```

The diagnostic output is read-only. It reports display state, labeled spaces, empty labeled spaces, duplicate labels, empty unlabeled spaces, and bad-window cache entries.

If a workspace command appears to hang after rebooting macOS, profile the shared yabai calls separately from window actions:

```fish
work_reload
set -gx WORKSPACE_DEBUG_YABAI 1
set -gx WORKSPACE_DEBUG_WINDOW 1
time gtd_chat
time gtd_calendar
set -e WORKSPACE_DEBUG_YABAI
set -e WORKSPACE_DEBUG_WINDOW
```

`WORKSPACE_YABAI_COMMAND_TIMEOUT_SECONDS` controls the timeout for shared yabai queries, display focus, and space operations. It defaults to `5` seconds. `WORKSPACE_YABAI_TIMEOUT_SECONDS` controls direct window operations through `ws_window` and defaults to `1` second.

Phase 8.5 adds conservative manual recovery commands:

```fish
work_bad_windows
work_clear_bad_windows
work_cleanup_empty_labeled_spaces
work_cleanup_empty_unlabeled_spaces
work_recover_light
```

The recovery rules are intentionally limited:

- `work_bad_windows` only prints cached bad yabai window IDs.
- `work_clear_bad_windows` only clears `/tmp/workspace-ws-window-bad`.
- `work_cleanup_empty_labeled_spaces` destroys only empty spaces with known workspace labels.
- `work_cleanup_empty_unlabeled_spaces` destroys empty unlabeled spaces except the current protected space.
- `work_recover_light` runs diagnostics, then the two empty-space cleanup commands, then diagnostics again.

`work_recover_light` does not move windows, does not apply layouts, and does not switch display profiles.

## Mode Commands

The workspace system currently supports three top-level work modes:

```fish
display_apply_solo
work_solo

display_apply_wide_left
work_wide

display_apply_tall_left
work_tall
```

The `display_apply_*` commands apply the display profile and reload workspace functions. The `work_*` commands then arrange the intended workspaces for that display mode.

Module-level entries can also be run directly:

```fish
coding_solo
coding_wide
coding_tall

research_solo
research_wide
research_tall

gtd_support_solo
gtd_support_wide
gtd_support_tall

gtd_review_solo
gtd_review_wide
gtd_review_tall

gtd_mail_solo
gtd_mail_wide
gtd_mail_tall

gtd_meeting_solo
gtd_meeting_wide
gtd_meeting_tall

office_writing_wide
office_writing_tall

office_slides_wide
office_slides_tall
```

## Module Conventions

All workspace modules follow these conventions:

1. A workspace function may reuse an existing labeled space instead of creating a new one.
2. A workspace function always normalizes the labeled space before arranging windows.
3. When a primary application for a workspace is missing, the workspace function may destroy an old empty labeled space with the same label before returning.
4. Unlabeled empty spaces are cleaned separately from labeled empty spaces.
5. Labeled empty spaces are cleaned by module-specific cleanup helpers such as:
   - `gtd_cleanup_*`
   - `coding_cleanup_*`
   - `office_cleanup_*`
   - `research_cleanup_*`

This separation keeps empty spaces under control without deleting meaningful structured workspaces too aggressively.

## ChatGPT Ownership Rule

`ChatGPT` is treated as a shared single-instance helper application across multiple modules.

The global ownership rule is:

**the last module invoked owns the `ChatGPT` window**

If `ChatGPT` appears in more than one workspace design, the most recently executed module function may move it into that module’s workspace.

This behavior is intentional and is the standard rule for the current workspace system.

## Stale Space Cleanup Rule

If a workspace depends on a required primary application, such as Word, PowerPoint, or Zotero, and that application is not currently available, the workspace function will:

1. check whether an old labeled space with the same label already exists
2. destroy that space if it is empty
3. return without creating a new workspace

This prevents old empty labeled spaces from persisting after application state changes.

## GTD Chat Special Note

`gtd_chat` uses the following windows as its core layout:

- `Keybase`
- `钉钉`
- `WeChat`
- `Messages`

`WhatsApp` is treated as best-effort. If it can be detected and moved reliably, it may be included. If it cannot be moved cleanly, the workspace still counts as valid without it.

So `WhatsApp` is not a strict success condition for `gtd_chat`.

## Reload Commands

The main reload commands are:

```fish
gtd_reload
coding_reload
office_reload
research_reload
```

These reload commands source both module-local functions and the shared helper functions in `workspace/common`.

## Status Commands

The main inspection commands are:

```fish
work_diagnostics
work_check
work_status
work_mode_status

gtd_status
coding_status
office_status
research_status
```

Mode-level inspection commands are:

```fish
gtd_mode_status
coding_mode_status
office_mode_status
research_mode_status
```

These commands are intended for day-to-day maintenance and regression checking after changes to workspace behavior.

Command-entry validation:

```fish
work_reload
work_command_check
```

`work_command_check` verifies that documented workspace, display, status, recovery, and hotkey entry functions are loaded.

## Recommended Daily Sequences

Single internal display:

```fish
display_apply_solo
work_solo
work_diagnostics
```

Wide external display:

```fish
display_apply_wide_left
work_wide
work_diagnostics
```

Tall external display:

```fish
display_apply_tall_left
work_tall
work_diagnostics
```

If diagnostics show only empty workspace spaces or stale bad-window cache entries, run:

```fish
work_recover_light
```

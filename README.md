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
- optional primary-display workspaces for module-specific fixed layouts

The system is designed to keep workspace behavior predictable, composable, and portable across machines.

This README is the daily-use and troubleshooting entry point. Ongoing maintenance tasks and longer-term design roadmap items live in `design-notes.md` under `Roadmap And TODO`.

## New Machine Bootstrap

On a new Mac or after a macOS/yabai reset, configure the workspace primary display UUID before relying on WIDE, TALL, or primary-display workspace commands.

Recommended bootstrap:

```fish
work_reload
detect_and_set_workspace_primary_display_uuid
get_workspace_primary_display_uuid
work_diagnostics
```

The workspace primary display is where fixed/control workspaces such as `gtd_chat`, `gtd_calendar`, and `coding_control` belong. On a MacBook it is usually the built-in display. On a Mac mini with one display, it is that only display. On a Mac mini with multiple displays, set it explicitly once.

`detect_and_set_workspace_primary_display_uuid` uses `yabai` display metadata as the source of truth. It keeps an existing connected primary UUID, automatically uses the only display in single-display setups, and can detect a MacBook built-in display through `displayplacer` when available. If it cannot determine the primary display confidently, inspect the current displays:

```fish
yabai -m query --displays | jq -r '.[] | "index=\(.index) uuid=\(.uuid) focus=\(.[\"has-focus\"]) frame=(\(.frame.x),\(.frame.y),\(.frame.w),\(.frame.h)) spaces=\(.spaces)"'
```

Then set the workspace primary display manually:

```fish
set_workspace_primary_display_uuid <display-uuid>
```

Confirm the stored value:

```fish
get_workspace_primary_display_uuid
```

The value is stored in the fish universal variable `WORKSPACE_PRIMARY_DISPLAY_UUID`, so it persists across future fish sessions for the same user.

This setup matters because fixed workspaces such as `gtd_chat`, `gtd_calendar`, and `coding_control` must stay anchored to the workspace primary display. External modes such as `work_wide` and `work_tall` use the configured primary UUID to identify a non-primary target display, falling back to the primary display when only one display exists. The macOS primary display is allowed to differ from the workspace primary display role.

## Common Helper Layer

Shared helpers are located in `workspace/common`.

They are responsible for:

- creating or reusing labeled spaces
- normalizing labeled spaces
- resolving target displays
- focusing displays and spaces safely
- cleaning unlabeled empty spaces
- resolving primary and external target display roles
- storing and reading the configured workspace primary display UUID
- best-effort detection of the workspace primary display UUID
- wrapping yabai and jq queries with bounded timeouts
- selecting and refreshing shared app windows consistently

Current core helpers include:

- `find_or_create_labeled_space`
- `prepare_labeled_space`
- `source_workspace_common`
- `workspace_status_snapshot`
- `workspace_mode_status_section`
- `cleanup_unlabeled_empty_spaces`
- `resolve_workspace_primary_display`
- `resolve_workspace_external_display`
- `ws_focus_display`
- `ws_focus_space`
- `ws_yabai`
- `ws_jq`
- `ws_query_windows`
- `workspace_find_app_window`
- `workspace_capture_app_window`
- `workspace_prepare_labeled_space`
- `workspace_focus_labeled_space`
- `workspace_retarget_contaminated_space`

## Inventory And Doctor

Two read-only inspection commands document and validate the workspace system without moving windows, changing spaces, or applying display profiles:

```fish
work_inventory
work_doctor
```

`work_inventory` prints the current workflow map: top-level entries, module entries, managed apps, display entries, common helpers, and external dependencies.

`work_doctor` runs read-only system checks:

- required tools: `fish`, `jq`, `yabai`, `displayplacer`, and `skhd`
- Mackup/runtime entry paths
- fish syntax for workspace functions and display profile scripts
- `work_reload`
- `work_command_check`
- read-only yabai display, space, and window queries
- duplicate labels, empty labeled spaces, and empty unlabeled spaces
- display role health
- bad-window cache summary

It returns nonzero only for failed checks. Warnings identify cleanup or environment follow-up without mutating state.

Additional loaded entry/helper commands include:

- `set_workspace_primary_display_uuid`
- `get_workspace_primary_display_uuid`
- `detect_and_set_workspace_primary_display_uuid`
- `work_diagnostics`
- `work_bad_windows`
- `work_clear_bad_windows`
- `workspace_cleanup_known_labeled_spaces`
- `cleanup_unlabeled_empty_spaces`
- `work_recover_light`
- `work_command_check`
- `ws_yabai`
- `ws_jq`
- `ws_query_windows`
- `ws_find_window`
- `ws_find_windows`
- `workspace_select_app_window`
- `workspace_refresh_app_window`
- `workspace_prepare_labeled_space`
- `workspace_focus_labeled_space`
- `workspace_debug_step`
- `workspace_run_step`

These helpers allow all module-level workspace functions to share the same lifecycle and display-selection logic.

## Diagnostics And Light Recovery

Use `work_diagnostics` first when a display transition or workspace command leaves the system in an unexpected state:

```fish
work_reload
work_diagnostics
```

The diagnostic output is read-only. It reports display state, labeled spaces, empty labeled spaces, duplicate labels, empty unlabeled spaces, and bad-window cache entries.

It also includes display role health:

- configured workspace primary display UUID and resolved primary display index
- resolved target display index and whether it is at `origin:(0,0)`
- Dock `orientation` and `autohide`
- warnings for display-role or Dock mismatches

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

`WORKSPACE_YABAI_QUERY_TIMEOUT_SECONDS` controls the timeout for shared yabai queries and defaults to `15` seconds because display queries can briefly stall after display-profile changes or Dock/yabai restarts. `WORKSPACE_YABAI_OPERATION_TIMEOUT_SECONDS` controls non-query `ws_yabai` operations such as display focus, space focus, and space destroy; it defaults to `3` seconds so one stuck operation does not make a full mode switch look hung. `WORKSPACE_YABAI_COMMAND_TIMEOUT_SECONDS` remains a global override for both categories. `WORKSPACE_YABAI_TIMEOUT_SECONDS` controls direct window operations through `ws_window` and defaults to `1` second.

If even read-only yabai queries such as `ws_yabai -m query --displays` or `ws_query_windows probe initial` hit the timeout, restart yabai before rerunning workspace commands:

```fish
yabai --restart-service
work_reload
```

After restart, confirm the query layer is responsive:

```fish
set -gx WORKSPACE_DEBUG_YABAI 1
time ws_yabai -m query --displays >/tmp/ws-displays.json
time ws_query_windows probe initial >/tmp/ws-query-probe.json
set -e WORKSPACE_DEBUG_YABAI
rm -f /tmp/ws-displays.json /tmp/ws-query-probe.json
```

For a mode command that appears slow but still returns eventually, enable step logging for one run:

```fish
set -gx WORKSPACE_DEBUG_STEPS 1
gtd_solo_all
set -e WORKSPACE_DEBUG_STEPS
```

If a window selector itself appears slow, enable selector-level logging for one run:

```fish
set -gx WORKSPACE_DEBUG_SELECT 1
gtd_solo_all
set -e WORKSPACE_DEBUG_SELECT
```

Phase 8.5 adds conservative manual recovery commands:

```fish
work_inventory
work_doctor
work_bad_windows --summary
work_bad_windows --expired
work_bad_windows --missing
work_clear_bad_windows --expired
workspace_cleanup_known_labeled_spaces
cleanup_unlabeled_empty_spaces
work_recover_light
work_display_health
```

The recovery rules are intentionally limited:

- `work_inventory` prints the static workflow map and dependencies.
- `work_doctor` runs read-only syntax, load, dependency, display, space, and cache checks.
- `work_bad_windows` only prints cached bad yabai window IDs and supports `--summary`, `--active`, `--expired`, `--present`, and `--missing`.
- `work_clear_bad_windows` only clears `/tmp/workspace-ws-window-bad`; use `--expired`, `--missing`, `--present`, or `--active` for targeted cleanup, and no flag or `--all` for full cache cleanup.
- `workspace_cleanup_known_labeled_spaces` destroys only empty spaces with known workspace labels.
- `cleanup_unlabeled_empty_spaces` destroys empty unlabeled spaces except the current protected space.
- `work_recover_light` runs diagnostics, then the two empty-space cleanup commands, then diagnostics again.

`work_recover_light` does not move windows, does not apply layouts, and does not switch display profiles.

`work_display_health [solo|wide|tall]` is a read-only display-role check. It reports whether the configured workspace primary display is present, which target display was resolved, whether the target display is at `origin:(0,0)`, whether the target is left of the primary display when two displays are present, whether the target display shape matches the expected mode, and whether Dock `orientation`/`autohide` match the workspace assumptions.

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

The `display_apply_*` commands apply the display profile, reload workspace functions, wait briefly for the display graph to settle, and run the matching `work_display_health` check. External display profiles resolve the currently connected external display at runtime instead of depending on a fixed external display UUID. The `work_*` commands then arrange the intended workspaces for that display mode.

`work_wide` arranges coding, research, office, and GTD wide workspaces. `work_tall` arranges the matching tall workspaces. Office workspaces are no-ops when Word or PowerPoint does not have an eligible window. GTD remains the last aggregate module so ChatGPT ownership is preserved for review workspaces in top-level external modes.

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

Window selection follows two shared patterns:

- Use `workspace_capture_app_window` when a workspace owns a simple app by name and needs it moved to a target space.
- Use `workspace_find_app_window` when a workspace only needs to select or confirm a movable app window.
- Use `ws_find_window` when a workspace needs title exclusion, app regex matching, non-empty title checks, or bad-window cache awareness.

All workspace JSON parsing should go through `ws_jq`, `ws_find_window`, `ws_find_windows`, `workspace_select_app_window`, `workspace_find_app_window`, or `workspace_capture_app_window`; direct `jq` pipelines are avoided inside workspace functions so parser timeouts remain bounded.

## ChatGPT Ownership Rule

`ChatGPT` is treated as a shared single-instance helper application across multiple modules.

The global ownership rule is:

**the last module invoked owns the `ChatGPT` window**

If `ChatGPT` appears in more than one workspace design, the most recently executed module function may move it into that module’s workspace.

Coding editor modes use `Codex` as the helper application instead of `ChatGPT`. In `coding_editor_solo`, `coding_editor_wide`, and `coding_editor_tall`, Codex is optional; when it is unavailable, VS Code uses the full target workspace.

ChatGPT-owning modes use `workspace_capture_app_window` to capture ChatGPT. If yabai reports ChatGPT but does not expose a movable window, the helper activates ChatGPT, polls for a movable window, retries the move once, and prints a warning if the window remains non-movable.

This behavior is intentional and is the standard rule for the current workspace system.

## Stale Space Cleanup Rule

If a workspace depends on a required primary application, such as Word, PowerPoint, or Zotero, and that application is not currently available, the workspace function will:

1. check whether an old labeled space with the same label already exists
2. destroy that space if it is empty
3. return without creating a new workspace

This prevents old empty labeled spaces from persisting after application state changes.

## GTD Support Dia Layout

`gtd_support_solo`, `gtd_support_wide`, and `gtd_support_tall` collect all non-minimized `Dia` windows that yabai reports as movable. If Dia exists but no movable window is available, they activate Dia once, refresh the window snapshot, and warn if yabai still cannot expose a movable Dia window.

Solo support layout:

- 1 Dia window: full space
- 2 Dia windows: top half and bottom half
- 3 Dia windows: two on the top half, one on the bottom half
- 4 or more Dia windows: two-column grid, filled top to bottom

Wide support layout:

- 1 Dia window: full space
- 2 Dia windows: left half and right half
- 3 Dia windows: three columns
- 4 or more Dia windows: two-row grid, filled left to right

Tall support layout:

- 1 Dia window: bottom half
- 2 Dia windows: top half and bottom half
- 3 Dia windows: two on the top half, one on the bottom half
- 4 or more Dia windows: two-column grid, filled top to bottom

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

Mode-level inspection is unified in:

```fish
work_mode_status
```

These commands are intended for day-to-day maintenance and regression checking after changes to workspace behavior.

Command-entry validation:

```fish
work_reload
work_command_check
```

`work_command_check` verifies that documented workspace, display, status, recovery, and hotkey entry functions are loaded.

## Recommended Daily Sequences

Before using the mode commands, keep these machine-level assumptions true:

- `WORKSPACE_PRIMARY_DISPLAY_UUID` is set to the display that should host fixed/control workspaces.
- macOS Dock is configured with auto-hide enabled.
- In external modes, the external display profile may or may not become the macOS primary display.
- Workspace primary/target roles are resolved by UUID, not by macOS primary display or display origin.
- `yabai`, `jq`, and `displayplacer` are available in `PATH`.

Check the core display role setup:

```fish
work_reload
get_workspace_primary_display_uuid
echo primary=(resolve_workspace_primary_display)
echo target=(resolve_workspace_external_display)
work_display_health
```

Check the Dock settings:

```fish
defaults read com.apple.dock orientation
defaults read com.apple.dock autohide
```

Expected Dock values:

```text
left
1
```

### Solo Primary Display

Use this when working only on the workspace primary display.

```fish
display_apply_solo
work_solo
work_display_health solo
work_diagnostics
```

Expected state:

- only the primary display is enabled
- the primary display is at `origin:(0,0)`
- `resolve_workspace_primary_display` returns the active display
- `resolve_workspace_external_display` falls back to the primary display because no non-primary display is connected
- fixed workspaces such as `gtd_chat`, `gtd_calendar`, and `coding_control` stay on the primary display

Equivalent hotkey:

```text
Fn + Shift + 0
```

### Wide External Display

Use this when the wide external monitor is connected on the left.

```fish
display_apply_wide_left
work_wide
work_display_health wide
work_diagnostics
```

Expected state:

- the wide external monitor is enabled and left of the workspace primary display
- the workspace primary display remains enabled to the right of the external monitor
- the external monitor may or may not be the macOS primary display depending on what macOS accepts from displayplacer
- `resolve_workspace_primary_display` returns the configured primary display
- `resolve_workspace_external_display wide` returns the wide target display
- wide task workspaces move to the external display
- fixed workspaces remain on the workspace primary display

Equivalent hotkey:

```text
Option + Shift + 0
```

### Tall External Display

Use this when the tall external monitor is connected on the left.

```fish
display_apply_tall_left
work_tall
work_display_health tall
work_diagnostics
```

Expected state:

- the tall external monitor is enabled and left of the workspace primary display
- the workspace primary display remains enabled to the right of the external monitor
- the external monitor may or may not be the macOS primary display depending on what macOS accepts from displayplacer
- `resolve_workspace_primary_display` returns the configured primary display
- `resolve_workspace_external_display tall` returns the tall target display
- tall task workspaces move to the external display
- fixed workspaces remain on the workspace primary display

Equivalent hotkey:

```text
Control + Shift + 0
```

### Post-Switch Checks

After switching display mode, check the actual display graph if windows or the Dock appear on the wrong screen:

```fish
yabai -m query --displays | jq -r '.[] | "index=\(.index) uuid=\(.uuid) focus=\(.[\"has-focus\"]) frame=(\(.frame.x),\(.frame.y),\(.frame.w),\(.frame.h)) spaces=\(.spaces)"'
echo primary=(resolve_workspace_primary_display)
echo target=(resolve_workspace_external_display)
work_display_health tall
```

For external modes, the target display should resolve to the non-primary display when one is connected. On single-display systems, target and primary intentionally resolve to the same display.

Use `work_display_health wide` after `display_apply_wide_left`, and `work_display_health tall` after `display_apply_tall_left`. If it reports target display role warnings, rerun the matching `display_apply_*` command. The `display_apply_*` commands return nonzero when their post-apply health check still has warnings, so SKHD bindings use `;` before `work_*` to keep workspace mode entry available even when display health warns.

If the Dock is configured correctly but does not hide or show from the expected edge, restart the Dock after applying the display profile:

```fish
killall Dock
```

If diagnostics show only empty workspace spaces or stale bad-window cache entries, run:

```fish
work_recover_light
```

If only bad-window cache entries are noisy, inspect and clean them explicitly:

```fish
work_bad_windows --summary
work_bad_windows --expired
work_clear_bad_windows --expired
```

`expired` means the cache entry is older than `WORKSPACE_BAD_WINDOW_TTL_SECONDS`, which defaults to `600`. `present_in_yabai=true` means yabai still reports that window ID, so inspect the app before clearing if the same ID repeatedly becomes bad again.

If `gtd_meeting_*` warns that Outlook exists but is not movable, inspect the GTD app diagnostics:

```fish
gtd_apps
```

Outlook should report `can_move=true` and `has_ax_reference=true`. If it does not, use the light Outlook recovery command:

```fish
gtd_reopen_outlook
gtd_meeting_tall
```

`gtd_find_outlook_window` uses the shared movable app-window helper. If Outlook remains present but non-movable after activation and polling, restart yabai to rebuild its window graph.

`gtd_reopen_outlook` does not quit Outlook. It clears Outlook entries from the workspace bad-window cache, asks Outlook to activate/reopen, then prints the current Outlook window diagnostics.

Meeting commands use `gtd_find_zoom_window` for Zoom and `gtd_find_teams_window` for Teams. They require movable main windows, exclude transient meeting/video/share windows, and clear recovered window IDs from the bad-window cache. Teams recognizes both `Microsoft Teams` and `MSTeams`.

All `gtd_meeting_*` modes also retarget contaminated labeled spaces before layout. If a previous meeting label points at a space mixed with non-meeting apps, the command clears that label and uses a clean meeting space.

`gtd_meeting_solo` uses a 1/3 + 2/3 layout on the workspace primary display: Zoom and Teams share the left third vertically, and Outlook uses the right two thirds.

`gtd_review_*` modes create or reuse the review workspace when at least one non-Finder review app is available: Preview, Notes, or ChatGPT. Finder is included in the layout when present, but Finder alone does not create a review workspace.

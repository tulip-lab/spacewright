# Workspace Design Notes

This file is the design-level source of truth for the workspace automation system. Daily commands and troubleshooting steps live in `README.md`; this document records the current rules, boundaries, and backlog.

## Design Goals

The workspace system is built around four goals:

1. predictable space labeling and reuse
2. minimal stale-space accumulation
3. portable cross-machine behavior
4. consistent layout semantics without hiding workflow-specific rules

The system is modular: GTD, coding, office, and research workflows can evolve independently while sharing common display, space, query, and recovery helpers.

## Current Architecture

### Display Roles

Business-level workspace functions do not hardcode display UUIDs. The workspace primary display UUID is stored once and resolved through helpers:

- `detect_and_set_workspace_primary_display_uuid`
- `set_workspace_primary_display_uuid <display-uuid>`
- `get_workspace_primary_display_uuid`
- `resolve_workspace_primary_display`
- `resolve_workspace_external_display`

Current display role rules:

- fixed/control workspaces use `resolve_workspace_primary_display`
- external task workspaces use `resolve_workspace_external_display`
- external resolution must fail closed on query failure
- fallback to the workspace primary display is allowed only after a successful display query confirms single-display operation

The workspace primary display role is separate from the macOS primary display. On MacBook setups it is commonly the built-in display. On Mac mini single-display setups it is the only display. On Mac mini multi-display setups it should be explicitly configured once.

### Display Profiles And Workspace Entry

Display profile functions apply monitor geometry only:

- `display_wide_left`
- `display_tall_left`
- `display_solo`

Mode entry is a two-step contract:

- `display_apply_solo; work_solo`
- `display_apply_wide_left; work_wide`
- `display_apply_tall_left; work_tall`

The whole-workspace hotkeys intentionally use `;` rather than `and` so `work_*` still runs if the display verification step reports a display mismatch.

`display_apply_*` commands:

- run the corresponding display profile
- fail fast if displayplacer fails
- reload display/workspace functions
- wait briefly through `display_verify_mode`
- run `work_display_health <mode>`

`WORKSPACE_DISPLAY_SETTLE_SECONDS` controls the post-profile wait and defaults to `0.8`.

SKHD top-level mode bindings use `display_apply_*; work_*` so display health warnings do not block workspace mode entry.

### Display Health

`work_display_health [solo|wide|tall]` is the focused read-only display-role check. It reports:

- configured workspace primary display UUID
- resolved primary and target display indexes
- secondary display count
- target display origin and left-of-primary health
- target display shape
- Dock `orientation` and `autohide`

Expected mode-specific state:

- `solo`: no secondary display is visible
- `wide`: target display is wider than tall and is left of the primary display when a secondary display is present
- `tall`: target display is taller than wide and is left of the primary display when a secondary display is present

`work_display_health <mode>` returns nonzero when warnings are present. Plain `work_display_health` remains a read-only report suitable for diagnostics.

Diagnostics do not apply display profiles, restart Dock, move spaces, or repair anything automatically. If external display health fails, rerun the matching `display_apply_*` command before entering the workspace mode again.

## Space And Label Rules

### Labeled Spaces

Workspace labels are structural ownership markers. Use:

- `find_or_create_labeled_space`
- `prepare_labeled_space`
- module cleanup wrappers around `cleanup_labeled_empty_spaces`

`prepare_labeled_space` clears the same label from other spaces before assigning it to the target space. This keeps label ownership unique across display transitions.

`find_or_create_labeled_space` does not rely on display focus to control new-space placement. It creates the space, identifies it by UUID difference, checks the actual display, and explicitly moves it to the target display when needed.

### Unlabeled Spaces

`cleanup_unlabeled_empty_spaces` handles transient empty spaces that carry no structural label. This stays separate from labeled-space cleanup to avoid deleting meaningful workspaces too aggressively.

`work_cleanup_empty_unlabeled_spaces` and `work_recover_light` are explicit manual recovery tools. They are not hidden inside normal workspace entry.

### Primary-App Absence

Some workspaces require a primary app, such as Code, Zotero, Thunderbird, Word, or PowerPoint. If the primary app is unavailable, the workspace function destroys an existing empty labeled space with the same label and returns without creating a new workspace.

This keeps status output accurate and reduces stale structural residue.

## Query, Parsing, And Window Movement

### Query Boundary

Use shared bounded helpers for yabai and JSON parsing:

- `ws_yabai`
- `ws_jq`
- `ws_query_windows`
- `ws_find_window`
- `ws_find_windows`
- `workspace_select_app_window`
- `workspace_find_app_window`
- `workspace_capture_app_window`
- `workspace_prepare_labeled_space`
- `workspace_focus_labeled_space`

Workspace functions should avoid direct `jq` pipelines where these helpers cover the behavior.

`ws_yabai` separates read-only query timeout from non-query operation timeout. Queries can wait longer; focus/destroy operations fail faster so mode switches do not appear stuck on one space operation.

If read-only queries repeatedly time out, recovery is explicit:

```fish
yabai --restart-service
work_reload
```

### Window Movement

`ws_window` is the wrapper for direct `yabai -m window ...` operations. It uses bounded timeouts and caches window IDs that time out under:

```text
/tmp/workspace-ws-window-bad
```

Move helpers move caller-provided IDs only. They do not rediscover other same-app windows during movement, because stale yabai IDs can cause repeated stalls.

Useful move helpers:

- `ws_move_app_to_space`
- `ws_move_app_pair_to_space`
- `ws_move_windows_to_space`
- `workspace_capture_app_window`

`workspace_find_app_window` is the default helper for simple app-name ownership. It selects a movable yabai window, can constrain to a target space, can activate the app and poll for a refreshed movable window, and clears recovered bad-window cache entries. Use this for ordinary single-window helper apps instead of hand-written `ws_find_window "<app>"` logic.

`workspace_capture_app_window` builds on that finder: it finds a movable app window, moves it to the target space, then confirms the app is present on that space. This is the preferred path for shared helper apps such as Codex in coding and ChatGPT in research, office, and GTD review workspaces.

`workspace_prepare_labeled_space` and `workspace_focus_labeled_space` own the repeated labeled-space entry sequence: create or reuse the space when needed, normalize the label/layout, focus the target display, run optional mode cleanup, focus the target space, and return control to the caller. Module functions still own app selection, move rules, and layout grids.

Layout geometry remains explicit in module functions or narrow module-specific helpers. There is no generic layout engine.

## Diagnostics And Recovery

### Diagnostics

Primary read-only commands:

- `work_inventory`
- `work_doctor`
- `work_diagnostics`
- `work_status`
- `work_mode_status`
- `work_check`
- `work_command_check`

`work_inventory` is the static workflow map. It records the top-level entries, module entries, managed apps, display entries, common helpers, and dependency boundaries in command output so the active system can be inspected without reading every function file.

`work_doctor` is the read-only validation entry. It checks required tools, Mackup/runtime paths, fish syntax, function reload, command availability, read-only yabai queries, display role health, duplicate labels, empty spaces, and bad-window cache summary. It must not move windows, switch spaces, apply display profiles, restart services, or cleanup state.

`work_diagnostics` reports display health, labeled spaces, empty labeled spaces, duplicate labels, empty unlabeled spaces, and bad-window cache summary.

`work_command_check` validates function availability after `work_reload`. It does not move windows, switch displays, or validate app presence.

### Bad Window Cache

`work_bad_windows --summary` reports total, active, expired, present-in-yabai, missing-from-yabai, and TTL counts.

Detailed filters:

- `work_bad_windows --active`
- `work_bad_windows --expired`
- `work_bad_windows --present`
- `work_bad_windows --missing`

Targeted cleanup:

- `work_clear_bad_windows --expired`
- `work_clear_bad_windows --missing`
- `work_clear_bad_windows --present`
- `work_clear_bad_windows --active`

No bad-window cleanup runs automatically from workspace mode entry, display profile application, or light recovery.

State meanings:

- `active`: newer than `WORKSPACE_BAD_WINDOW_TTL_SECONDS`
- `expired`: old enough that selectors no longer need to skip it for performance protection
- `present_in_yabai=true`: still exists in the current yabai graph and may need app-level investigation
- `present_in_yabai=false`: likely stale and usually safe to clear explicitly

### Light Recovery

`work_recover_light` is intentionally conservative. It runs diagnostics, empty labeled-space cleanup, empty unlabeled-space cleanup, and diagnostics again.

It does not:

- move application windows
- apply grid layouts
- switch display profiles
- restart Dock or yabai

## Mode And Cleanup Model

The active mode vocabulary is:

- `solo`
- `wide`
- `tall`

Aggregate entries such as `gtd_tall`, `gtd_wide`, `coding_tall`, `coding_wide`, `office_tall`, and `office_wide` own mode-level labeled cleanup. During child module calls, they set:

```fish
WORKSPACE_SKIP_LABELED_CLEANUP=1
```

This prevents repeated labeled-space scans and destroy attempts while preserving standalone module behavior.

Common cleanup wrappers are intentionally thin and mode-named:

- `*_cleanup_solo_spaces`
- `*_cleanup_wide_spaces`
- `*_cleanup_tall_spaces`

## GTD Ownership Rules

### ChatGPT

`ChatGPT` is shared by multiple workflows. The current global rule is:

**the last invoked module owns the `ChatGPT` window**

This keeps behavior deterministic without hidden precedence rules.

ChatGPT-owning workspaces capture a movable `ChatGPT` window through `workspace_capture_app_window`. If ChatGPT exists but yabai does not expose a movable window, the helper activates ChatGPT, polls for a refreshed movable window, retries the move once, and warns when yabai still cannot move it.

`gtd_find_chatgpt_window` remains as a narrow compatibility wrapper around the shared helper. New modules should call `workspace_find_app_window` or `workspace_capture_app_window` directly unless ChatGPT develops GTD-specific selection rules.

Coding editor modes use `Codex` instead of `ChatGPT` as the optional helper app. If Codex is not available, VS Code uses the full coding editor workspace.

In `gtd_solo_all`, review runs after meeting so GTD review is the final SOLO owner for ChatGPT.

### Notes And Dia

`Notes` is owned by `gtd_review_*`.

`gtd_review_*` no longer requires Preview as the primary app. A review workspace is eligible when Preview, Notes, or ChatGPT is present. Finder is still included when available, but Finder alone is intentionally not enough to create a review workspace because Finder is commonly present outside review work.

`Dia` is owned by `gtd_support_*`.

This avoids moving a single Notes window back and forth between support and review during aggregate entries.

### GTD Support Dia Layout

All GTD support modes collect every non-minimized Dia window that yabai reports as movable through `gtd_support_find_dia_windows`. If Dia is present but no movable Dia window is available after activation, the helper warns and suggests restarting yabai because the yabai window graph may be stale.

If Dia exists but no movable Dia window is exposed, the helper activates Dia once, refreshes the window snapshot, and fails closed with a warning if Dia remains non-movable.

`gtd_support_layout_dia_windows` applies mode-specific layouts:

- solo: one full-screen; multiple Dia windows use a compact top/bottom or two-column grid
- wide: one full-screen; two or three use horizontal columns; four or more use a two-row grid
- tall: one bottom half; two top/bottom; three with two on top and one on bottom; four or more use a two-column grid

This multi-window policy is deliberately scoped to GTD support. Meeting and review workspaces keep app-specific selection rules until real failures justify broadening multi-window ownership.

### GTD Meeting

Outlook selection goes through `gtd_find_outlook_window`, which returns only movable Outlook windows and can prefer a target-space Outlook window when one exists.

If Outlook exists but no movable Outlook window is available, meeting commands warn instead of pretending Outlook was moved.

`gtd_find_outlook_window` uses the shared movable app-window helper for Outlook capture. If Outlook exists but yabai does not expose a movable AX window after activation and polling, it warns and suggests restarting yabai because the yabai window graph may contain a stale Outlook reference.

`gtd_reopen_outlook` is a light manual recovery command: it clears Outlook bad-window cache entries, activates/reopens Outlook, and prints Outlook window diagnostics.

Zoom selection goes through `gtd_find_zoom_window`, which requires a movable main window, excludes transient meeting/video/share/screen/mini windows, and clears recovered Zoom entries from the bad-window cache. Final meeting-layout verification calls it with `--target-only` so a Zoom window on another space does not count as successfully placed.

Teams selection goes through `gtd_find_teams_window`, which recognizes both `Microsoft Teams` and `MSTeams`, requires a movable main window, excludes transient meeting/video/call/share/screen/mini windows, and clears recovered Teams entries from the bad-window cache. Final meeting-layout verification calls it with `--target-only` so a Teams window on another space triggers a retry instead of being treated as success.

All `gtd_meeting_*` modes use `workspace_retarget_contaminated_space` before preparing the labeled space. If the existing meeting label points at a space that contains non-meeting apps, the label is cleared and a clean meeting space is selected instead of mixing the workflow into a contaminated space.

`gtd_meeting_solo`, `gtd_meeting_tall`, and `gtd_meeting_wide` retry captured Zoom/Teams moves when the first move does not place the captured window on the target space.

Expected meeting behavior:

- Microsoft Outlook, zoom.us, and Microsoft Teams remain together in GTD meeting spaces
- Outlook-specific recovery stays in `gtd_find_outlook_window` and `gtd_reopen_outlook`
- Zoom-specific selection and bad-window recovery stays in `gtd_find_zoom_window`
- Teams-specific selection and bad-window recovery stays in `gtd_find_teams_window`
- `gtd_meeting_solo` uses a 1/3 + 2/3 layout: Zoom and Teams share the left third vertically, while Outlook owns the right two thirds.

### GTD Chat

The core GTD chat layout is:

- Keybase
- 钉钉
- WeChat
- Messages

WhatsApp is best-effort. Its window behavior is less stable in some sessions, so it should not make the whole chat workspace fragile.

## Abstraction Policy

Keep module-level workspace behavior explicit and readable.

Add shared helpers only when they remove stable repeated mechanics without hiding app ownership, query failure handling, or layout geometry.

Current accepted helper layers:

- display resolution helpers
- bounded yabai/query/parser helpers
- labeled/unlabeled cleanup helpers
- simple window selection helpers
- caller-provided window move helpers
- narrow GTD support Dia helpers

Current non-goals:

- no generic workflow engine
- no generic layout DSL
- no hidden automatic display/Dock/yabai repair
- no config-driven replacement of app-specific recovery logic

## Validation

For fish syntax changes:

```fish
fish -n path/to/file.fish
```

For command availability:

```fish
work_reload
work_command_check
```

For read-only health:

```fish
work_diagnostics
work_display_health
work_display_health tall
```

Do not run layout-changing workspace commands or display-changing commands during validation unless active window/display movement is explicitly intended.

## Roadmap And TODO

The workspace system is currently structurally stable. Future work should be incremental, evidence-driven, and biased toward keeping public entry commands stable.

### Maintenance Backlog

#### Now

##### Verify Current Workspace Behavior In Daily Use

Watch:

- `work_solo`, `work_tall`, and `work_wide`
- `office_wide` and `office_tall` through the top-level external-display entries
- `gtd_meeting_*` for Outlook, Zoom, and Teams placement
- `gtd_support_*` for multiple Dia windows
- ChatGPT ownership when moving between GTD review, office, and research
- bad-window cache summaries after repeated workspace transitions

Collect read-only evidence before changing code:

- `gtd_apps`
- `work_bad_windows --summary`
- `work_bad_windows --expired`
- `work_diagnostics`
- `WORKSPACE_DEBUG_STEPS=1` for one rerun of the affected mode

##### Final Diff Review Before Commit

Review the current workspace diff by behavior group:

- query, timeout, and selector helpers
- display profile health and SKHD chaining
- GTD meeting, review, and support behavior
- bad-window cache maintenance
- README and design-note consistency

Confirm default paths do not enable debug output. `WORKSPACE_DEBUG_STEPS`, `WORKSPACE_DEBUG_SELECT`, `WORKSPACE_DEBUG_WINDOW`, and `WORKSPACE_DEBUG_YABAI` should remain opt-in.

##### Preserve External Display Fail-Closed Behavior

Future edits to display helpers must preserve:

- query failure returns nonzero
- missing target display prevents labeled-space creation
- fallback to internal happens only after a successful query confirms single-display operation

#### Next

##### Extract A Small Meeting Fallback Helper

`gtd_meeting_tall` and `gtd_meeting_wide` share the same fallback pattern for Zoom and Teams:

- capture initial window id
- move captured windows
- query final target space
- retry a missing app once with the initial id

If this remains stable, extract a small helper so tall and wide do not drift. Keep Outlook recovery in Outlook-specific helpers.

##### Watch Meeting And Review Multi-Window Behavior

Before changing meeting or review ownership, watch:

- whether multiple Outlook, Zoom, or Teams windows should move together
- whether ChatGPT, Notes, Preview, or Finder should ever move as multi-window sets
- whether moving all same-app windows would steal windows from another active context

Do not generalize GTD support's Dia policy into broad multi-window ownership without concrete failures from real use.

##### Improve Diagnostic Summaries

Possible improvements:

- stronger summary output in `work_check`
- compact one-line health summary
- clearer grouping for display-mode mismatches
- better separation of active vs historical warning signals

Recovery mechanics should remain explicit rather than automatic.

### Watchlist

##### ChatGPT Ownership

The current last-caller rule is acceptable for daily use. Future refinement may make ChatGPT capture behavior more explicit by distinguishing active capture from opportunistic inclusion.

##### Outlook, Teams, And Bad-Window Cache Behavior

Watch for:

- Outlook present but `can_move=false` or `has_ax_reference=false`
- Zoom present but only transient meeting/video/share windows are selectable
- Teams present under either `Microsoft Teams` or `MSTeams` but not moved after a first attempt
- expired bad-window cache entries that correspond to currently visible meeting windows
- repeated need to rerun `gtd_meeting_solo`, `gtd_meeting_tall`, or `gtd_meeting_wide`

Inspect with `gtd_apps`, `work_bad_windows --summary`, and filtered `work_bad_windows` output before changing code.

##### WhatsApp Compatibility

`gtd_chat` treats WhatsApp as best-effort. If WhatsApp becomes important, improve diagnostics first, then decide whether it should become a stronger layout dependency.

##### Residual Unlabeled Spaces

`work_recover_light` can clean empty unlabeled spaces manually. If transient unlabeled spaces become frequent, improve diagnostics before adding cleanup to workflow commands.

##### Dock And Primary Display Behavior

External profiles intentionally place the external display at `origin:(0,0)` in WIDE and TALL modes. Watch for:

- Dock not hiding or showing after display-profile changes
- Dock appearing on the workspace primary display after external mode entry
- `resolve_workspace_external_display` returning the workspace primary display while a secondary monitor is connected
- yabai display queries timing out immediately after Dock or display changes

Runtime recovery should remain explicit, such as `killall Dock`, rather than hidden inside workspace entry commands.

### Product/Design Roadmap

#### Configurable Workspace Definitions

This is the next major-version direction, but it should wait until the current fish-based workspace version is confirmed stable in daily use.

The goal is to make stable workspace definitions configurable without turning the system into a generic workflow engine. Public command entry points should remain stable. For example, users should still run `coding_control`, `gtd_meeting_tall`, or `work_tall`; those commands may internally use config later.

Potential configuration target:

- workspace labels
- target display role: internal, external, or fallback rules
- app/window selectors
- window positions
- mode-specific cleanup hooks

Potential first config file:

```text
.config/fish/functions/workspace/config/workspaces.json
```

The first config shape should stay deliberately small:

```json
{
  "coding_control": {
    "label": "coding_control",
    "display_role": "internal",
    "space_layout": "float",
    "required_windows": ["smartgit"],
    "windows": {
      "smartgit": {
        "app": "SmartGit",
        "movable": true,
        "positions": [
          { "move_abs": [300, 60] },
          { "resize_abs": [1200, 1040] }
        ]
      }
    }
  }
}
```

Non-goals:

- do not configure display UUID resolution
- do not configure bad-window cache mechanics
- do not configure raw yabai timeout behavior
- do not encode complex app recovery logic directly in JSON; config should name the app and policy, while fish helpers implement recovery
- do not replace public fish entry commands such as `coding_control`, `gtd_meeting_tall`, or `work_tall`
- do not support arbitrary jq expressions, conditionals, loops, or fallback chains in JSON
- do not migrate Outlook, Dia, WhatsApp, or other special recovery behavior into config in the first version

Recommended implementation stages:

1. **Schema and read-only validation**
   Add `workspaces.json`, `workspace_config_check`, and `workspace_config_get <workspace>`.
   This stage must not move windows, create spaces, or apply layouts.

2. **Migrate `coding_control` first**
   `coding_control` is the best pilot because it targets the workspace primary display, has clear apps, uses absolute placement, and has little app-specific recovery logic.
   Keep `coding_control` as the public entry point and call a configured runner internally.

3. **Migrate simple repeated wide/tall modules**
   Candidate modules:
   - `gtd_mail_wide/tall`
   - `research_wide/tall`
   - `office_writing_wide/tall`
   - `office_slides_wide/tall`
   - `coding_editor_wide/tall`

4. **Evaluate GTD meeting after the simple modules**
   `gtd_meeting_*` may use configured final layout later, but Outlook recovery should remain in fish helpers such as `gtd_find_outlook_window` and `gtd_reopen_outlook`.

5. **Leave complex ownership modules until last**
   Keep these fish-first until there is strong evidence that config helps:
   - `gtd_chat`
   - `gtd_review_*`
   - `gtd_support_*`
   - ChatGPT ownership-sensitive workspaces

Likely helper set:

- `workspace_config_check`
- `workspace_config_get <workspace>`
- `workspace_select_configured_windows <workspace>`
- `workspace_prepare_configured_space <workspace>`
- `workspace_apply_configured_layout <workspace>`
- `workspace_run_configured <workspace>`

Technical guardrails:

- fail closed on missing config, invalid schema, jq failure, display query failure, or missing required windows
- do not create spaces or move windows when config validation fails
- keep selectors explainable: exact app, app regex, title exclusion, movable, visible, and non-empty title are enough for the first version
- keep layouts simple: `grid`, `move_abs`, and `resize_abs` are enough for the first version
- add `WORKSPACE_DEBUG_CONFIG=1` for selected workspace name, selector result, window id, and applied position
- validate config independently from runtime movement
- update README only for user-facing commands; keep design boundaries here

#### Internal Fixed Workspaces For Office Or Research

Office and research currently have wide/tall external task workspaces only. Future workflow evolution may justify primary-display fixed support spaces similar to `gtd_chat`, `gtd_calendar`, or `coding_control`.

#### Continue Abstraction Cleanup Carefully

Good candidates remain:

- required-primary-window absence helper
- small meeting fallback helper
- final on-space capture helper for simple primary/helper pairs

Avoid broad abstractions that hide app ownership, recovery rules, or layout geometry.

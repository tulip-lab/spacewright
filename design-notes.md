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

### Module Entry Files

Public command names remain stable for shell and skhd use, but simple mode wrappers are grouped by module:

- `coding/coding_entries.fish`
- `research/research_entries.fish`
- `office/office_entries.fish`
- `gtd/gtd_entries.fish`

Module reloaders source these grouped entry files, plus separate internal helpers when app-specific recovery or multi-window behavior needs its own implementation. This avoids one tiny file per solo/wide/tall wrapper while keeping the workflow boundary explicit.

Top-level and common wrappers follow the same grouping rule:

- `common/workspace_manifest.fish` defines the read-only declaration rows used by inventory, command checks, top-level dry-run output, and smoke dry-run coverage
- `common/work_entries.fish` defines `work_solo`, `work_wide`, and `work_tall`
- `display/display_entries.fish` defines `display_reload`, `display_verify_mode`, `display_apply_*` entries, and their shared profile runner
- `common/workspace_status_helpers.fish` defines status snapshots, mode status, simple module status wrappers, `work_status`, `work_mode_status`, and `work_check`
- `common/workspace_display_roles.fish` defines primary display UUID storage and display-role resolvers
- `common/workspace_runners.fish` defines step, cleanup-spec, and mode-step runners
- `common/workspace_module_reloads.fish` defines `gtd_reload`, `coding_reload`, `office_reload`, and `research_reload`
- `common/workspace_labeled_space_lifecycle.fish` defines labeled-space creation, label normalization, and empty-label helpers
- `common/workspace_labeled_space_focus.fish` defines labeled-space focus and prepare helpers
- `common/workspace_space_fallback.fish` defines fallback-space movement by UUID
- `common/workspace_app_window_selectors.fish` defines shared app-window and app-key window selectors
- `common/workspace_app_window_lifecycle.fish` defines refresh, find, and capture helpers
- `common/workspace_app_space_fallback.fish` defines fallback metadata for present app-key windows
- `common/workspace_app_bounds.fish` defines AppleScript bounds fallback helpers
- `common/ws_core.fish` defines the core yabai/jq query and focus wrappers

Keep public command names stable for shell and skhd callers. Prefer grouping tiny same-layer wrappers by responsibility over creating one file for every public function.

### Read-Only Manifest Layer

`common/workspace_manifest.fish` is the current shared declaration layer. It records stable facts that are useful for inspection and validation:

- top-level entries and their child command lists
- module entries and managed apps
- workspace command map rows
- display entry summaries
- common helper summaries
- external dependencies
- commands that must be loaded by `work_command_check`
- commands that should support `--dry-run` in `work_smoke`

This manifest is deliberately fish-based and read-only. It is not a generic runtime engine, does not contain layouts, and does not replace GTD-specific behavior. `work_inventory`, `work_command_check`, `work_smoke`, and top-level `work_* --dry-run` use it so documentation and checks do not maintain separate copies of the same command lists.

Runtime movement behavior remains in the existing entry functions and module helpers. `work_solo`, `work_wide`, and `work_tall` still execute their steps explicitly so this maintenance pass does not change window movement order or fallback behavior.

If a public entry is added, renamed, or retired, update `workspace_manifest.fish` together with the module entry file, `skhd` documentation if a hotkey changes, and this design note if the ownership or mode composition changes.

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

- `display_apply_wide_left`
- `display_apply_tall_left`
- `display_apply_solo`

Mode entry is a two-step contract:

- `display_apply_solo; work_solo`
- `display_apply_wide_left; work_wide`
- `display_apply_tall_left; work_tall`

The whole-workspace hotkeys intentionally use `;` rather than `and` so `work_*` still runs if the display verification step reports a display mismatch.

In top-level `work_wide` and `work_tall`, GTD remains the final ChatGPT-owning aggregate, but `coding_control` runs after GTD. This is intentional: when SmartGit is present without a movable AX window, the only reliable recovery is to make SmartGit's current Space the fixed control Space, so it must run after meeting fallback paths that may temporarily own the same unmovable-window Space.

Every public wide/tall entry uses `workspace_run_finalized_entry`. Nested module calls share a depth guard, so only the outermost entry collects Sandbox windows, cleans empty Spaces, orders and verifies labels, and restores focus. Solo aggregates establish a non-finalizing scope; direct mode-less primary entries finalize only when `workspace_detect_display_mode` reliably returns wide or tall.

The ownership policy's machine-readable app keys define the Sandbox exclusion boundary. A managed app is excluded in full even when its policy selects only one window. Other movable windows are collected unless they are on Home, sticky, or native fullscreen. The current-mode Sandbox is `sandbox_wide` or `sandbox_tall` on the external display, uses balanced BSP layout, and follows the meeting workspace in external order. Opposite-mode Sandbox windows migrate because their apps remain unmanaged, after which strict cleanup deletes the empty old Sandbox.

Finalization captures the lowest-index unlabeled primary Space as Home by UUID. Home and its windows are protected; no Home is created when absent. Empty-Space cleanup uses a live window snapshot, treats sticky-only Spaces as empty, and retains at least one survivor on every display. Ordering then places Home before `coding_control`, `gtd_chat`, and `gtd_calendar`, and places existing external labels in the business order ending with Sandbox. Verification rejects unmanaged interleaving, retries ordering once, and fails after a second drift. Final focus is resolved by UUID rather than a stale Mission Control index. `work_diagnostics` reports whether macOS recent-use Space reordering is disabled but does not modify the preference.

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

Diagnostics do not apply display profiles, restart Dock, restart yabai, move spaces, or repair anything automatically. If external display health fails, rerun the matching `display_apply_*` command before entering the workspace mode again.

## Space And Label Rules

### Labeled Spaces

Workspace labels are structural ownership markers. Use:

- `find_or_create_labeled_space`
- `prepare_labeled_space`
- module cleanup wrappers around `cleanup_labeled_empty_spaces`

`prepare_labeled_space` clears the same label from other spaces before assigning it to the target space. This keeps label ownership unique across display transitions.

`find_or_create_labeled_space` does not rely on display focus to control new-space placement. It creates the space, identifies it by UUID difference, checks the actual display, and explicitly moves it to the target display when needed.

Empty labeled-space cleanup is opportunistic. Cleanup Space snapshots use a short timeout and skip cleanup on query failure so a transient slow yabai Space query does not block the requested layout.
When a mode entry asks for multiple cleanup specs, `workspace_run_cleanup_specs` shares one cleanup Space snapshot across those specs instead of querying yabai once per mode.

### Unlabeled Spaces

`cleanup_unlabeled_empty_spaces` handles transient empty spaces that carry no structural label. This stays separate from labeled-space cleanup to avoid deleting meaningful workspaces too aggressively.

`cleanup_unlabeled_empty_spaces` and `work_recover_light` are explicit manual recovery tools. They are not hidden inside normal workspace entry.

### Primary-App Absence

Some workspaces require a primary app, such as Code, Zotero, Thunderbird, Word, or PowerPoint. If the primary app is unavailable, the workspace function destroys an existing empty labeled space with the same label and returns without creating a new workspace.

This keeps status output accurate and reduces stale structural residue.

## Query, Parsing, And Window Movement

### Query Boundary

Use shared bounded helpers for yabai and JSON parsing:

- `ws_yabai`
- `ws_jq`
- `ws_query_displays`
- `ws_query_spaces`
- `ws_query_current_display`
- `ws_query_current_space`
- `ws_query_windows`
- `ws_find_window`
- `ws_find_windows`
- `workspace_select_app_window`
- `workspace_find_app_window`
- `workspace_capture_app_window`
- `workspace_app_key_window_info`
- `workspace_app_key_windows`
- `workspace_app_key_space_fallback_info`
- `workspace_space_non_owned_windows`
- `workspace_apply_app_key_absolute_bounds`
- `workspace_snapshot`
- `workspace_plan`
- `workspace_verify`
- `workspace_prepare_labeled_space`
- `workspace_focus_labeled_space`
- `workspace_focus_space_fallback`
- `workspace_evict_non_owned_windows_from_space`

Workspace functions should avoid direct `jq` pipelines where these helpers cover the behavior.

`ws_yabai` separates read-only query timeout from non-query operation timeout. Queries can wait longer; focus/destroy operations fail faster so mode switches do not appear stuck on one space operation. `ws_focus_display` and `ws_focus_space` call yabai focus directly and treat `already focused` as success, avoiding current-focus query stalls on the hot path. `ws_query_displays`, `ws_query_spaces`, `ws_query_current_display`, and `ws_query_current_space` retry a failed query once before failing the caller. `ws_query_windows` first tries the full yabai window query, then falls back to per-Space window queries and merges the arrays when the full query fails. This keeps workspace entry points from failing before app-specific recovery logic can run.

If read-only queries repeatedly time out, recovery is explicit:

```fish
ws_restart_yabai manual
work_reload
```

`ws_restart_yabai` restarts the loaded legacy `com.asmvik.yabai` LaunchAgent
through `launchctl kickstart` when present, and otherwise delegates to yabai's
standard service command.

### Window Movement

`ws_window` is the wrapper for direct `yabai -m window ...` operations. It uses bounded timeouts and caches window IDs that time out under:

```text
/tmp/workspace-ws-window-bad
```

Move helpers move caller-provided IDs only. They do not rediscover other same-app windows during movement, because stale yabai IDs can cause repeated stalls.

Useful move helpers:

- `ws_move_windows_to_space`
- `workspace_capture_app_window`

`workspace_find_app_window` is the default helper for simple app-name ownership. It selects a movable yabai window, can constrain to a target space, can activate the app and poll for a refreshed movable window, and clears recovered bad-window cache entries. Use this for ordinary single-window helper apps instead of hand-written `ws_find_window "<app>"` logic. When a caller is confirming that a window landed on a specific target space, combine `--space` with `--target-only` so the finder cannot satisfy the check with the same app on another space.

`workspace_capture_app_window` builds on that finder: it finds a movable app window, moves it to the target space, then confirms the app is present on that space. It accepts either a concrete app name or an app key; app-key capture is preferred when the app is in the registry. This is the preferred path for shared helper apps such as ChatGPT in coding, office, GTD AI, and GTD review workspaces, and Claude in research workspaces.

`workspace_app_name`, `workspace_app_names`, `workspace_app_names_json`, and `workspace_app_regex` are the central app-name registry. Entry wrappers should use app keys when possible; module-specific helpers can still use explicit names when the app has special selection behavior, but they should source those names through the registry.

`workspace_ownership_policy_rows` is the static read-only app ownership registry used by `work_inventory`. It documents whether each workspace treats an app as a single selected window, all movable windows, an optional helper, or a fallback-space owner. It does not drive runtime layout decisions; module-specific helpers remain the source of behavioral truth.

Fixed primary-display workspaces such as `coding_control`, `gtd_chat`, and `gtd_calendar` use app-key finders for ordinary app windows, then retry once when a final target-space check misses. Module-specific selectors stay local only for real special cases such as Dia multi-window layout or Zoom/Teams meeting-window title policy.

`workspace_prepare_labeled_space` and `workspace_focus_labeled_space` own the repeated labeled-space entry sequence: create or reuse the space when needed, normalize the label/layout, focus the target display, run optional mode cleanup, focus the target space, and return control to the caller.

When a module already has a bounded yabai window JSON snapshot, `workspace_app_key_window_info` extracts app-key metadata from that snapshot and `workspace_app_key_windows` extracts matching app-key window ids so modules do not hand-roll app-name matching and movable checks. When an app-key window is present but remains non-movable, `workspace_app_key_space_fallback_info` identifies that app's current window, space, and display using the central app-name registry. `workspace_focus_space_fallback` then moves that space to the requested display by UUID, normalizes the label/layout, and focuses it. SmartGit coding-control fallback, Thunderbird mail fallback, Zoom meeting fallback, Preview/Notes review fallback, DingTalk chat fallback, and Calendar fallback all use this shared current-space fallback path. After such a fallback space becomes the target, `workspace_evict_non_owned_windows_from_space` moves movable non-owned windows into an unlabeled holding space; non-owned unmovable windows are reported but not forced. Holding-space selection uses live window membership and treats sticky-only spaces as empty, so stale window ids in `.spaces[].windows` do not block fallback eviction.

`workspace_retarget_contaminated_space` is used when preserving a label on a mixed workspace would keep unrelated apps inside the workflow. `coding_control`, `gtd_chat`, `gtd_meeting_*`, and `gtd_review_*` use it to clear the old label and continue on a clean labeled space when their current target contains non-owned windows. `coding_control` treats KeePassXC/KeePassX and Portfolio Performance as owned control apps alongside Warp, SmartGit, and FlClash/Thaw. Portfolio Performance is an optional single-window app placed at `(420,180)` with size `1220x852`; it is not launched when absent. FlClash/Thaw ownership uses movable non-minimized windows, not only windows that yabai currently marks visible.

`workspace_apply_primary_helper_space` owns the stable single-primary/single-helper workflow. Entry functions provide label, display role, app keys, cleanup specs, and grid geometry. The helper selects the required primary app through `workspace_find_app_key_window`, tries every registered app name for that key, confirms the primary window lands on the target space after moving, retries once if it does not, and fails with a warning rather than silently arranging an empty target. When an app is present but yabai does not expose a movable window, `workspace_find_app_window` focuses the app's current space before activating and re-querying it, then uses shared `ws_recover_yabai_once` restart recovery before returning non-movable. Coding editor wide/tall modes use VS Code as the required primary and an already-open ChatGPT window as the optional helper; solo remains VS Code-only. Research modes use Zotero as the required primary and an already-open Claude window as the optional helper.

`office_apply_document_space` owns Office writing and slides workspaces. It requires at least one movable Word or PowerPoint window, captures one ChatGPT helper window when present, moves all movable document windows to the target, and applies count-aware layouts for wide and tall modes.

`--primary-space-fallback` is reserved for apps that can stay visible in yabai while lacking an AX-backed movable window. GTD mail enables this for Thunderbird: if Thunderbird remains non-movable, its current space becomes the mail workspace and is moved/labeled as the target through the shared current-space fallback helpers. Outlook is an optional single-window helper in GTD mail. Because yabai cannot resize a window without a movable AX reference, the fallback applies the requested grid through `workspace_apply_app_key_grid_bounds`, which first sets the largest scriptable app window's AppleScript bounds from the target display frame, then falls back to System Events position/size when the app-specific AppleScript path fails. Fixed pixel fallback, currently used by SmartGit in `coding_control`, uses `workspace_apply_app_key_absolute_bounds` with the same AppleScript/System Events order.

GTD-specific helpers deliberately stay module-local:

- `gtd_apply_meeting_space` for Zoom and Teams selection/retry behavior
- `gtd_apply_review_space` for Finder, Preview, ChatGPT, and Notes ownership
- `gtd_apply_support_space` for multiple Dia windows and Dia-specific layout

Layout geometry remains explicit in entry wrappers or narrow module-specific helpers. There is no broad generic layout engine.

Dry-run is intentionally shallow: it reports declared workflow metadata and returns before yabai queries or mutation. Use `work_smoke` to verify dry-run coverage after structural edits.

## Diagnostics And Recovery

### Diagnostics

Primary read-only commands:

- `work_inventory`
- `yabai_doctor`
- `work_doctor`
- `work_audit`
- `work_diagnostics`
- `work_status`
- `work_mode_status`
- `work_check`
- `work_command_check`

`work_inventory` is the static workflow map. It records the top-level entries, module entries, managed apps, ownership policies, display entries, common helpers, and dependency boundaries in command output so the active system can be inspected without reading every function file.

`yabai_doctor` is the dedicated yabai runtime check. Without options it is
strictly read-only: it resolves the active binary and version, checks whether
the required Homebrew HEAD build is active, confirms the loaded LaunchAgent is
running, performs bounded display/Space/window queries, hashes the binary, and
matches that hash against `sudo -n -l`. It does not load the scripting
addition, restart a service, open System Settings, or create a Space.

`yabai_doctor --repair` is the explicit state-changing recovery path. Its
dependency order is:

```text
HEAD binary -> matching sudoers hash -> load scripting addition ->
restart loaded LaunchAgent -> Accessibility/query check ->
temporary Space create/destroy probe -> work_doctor
```

The sudoers candidate is validated with `visudo -cf` before installation and
its temporary file is removed on success or failure. The Space probe destroys
only one UUID proven absent from the pre-create snapshot and present in the
post-create snapshot; missing or ambiguous identity stops without deletion.
Repair never changes SIP, resets TCC, approves privacy prompts, moves windows,
applies a display profile, or invokes a workspace layout entry. When the new
binary lacks Accessibility permission, it opens the relevant System Settings
page and requires the user to re-add `/opt/homebrew/bin/yabai`.

`work_audit` is the read-only architecture drift check. It verifies solo/wide/tall wrapper symmetry through dry-run output, checks ownership policy coverage, confirms fallback and multi-window helper availability, and distinguishes empty labels that are allowlisted by design from suspicious empty labeled Spaces in the live read-only snapshot.

`work_doctor` is the read-only validation entry. It checks required tools, Mackup/runtime paths, fish syntax, function reload, command availability, read-only yabai queries, display role health, duplicate labels, empty spaces, and bad-window cache summary. It must not move windows, switch spaces, apply display profiles, restart services, or cleanup state.

`work_diagnostics` reports display health, labeled spaces, empty labeled spaces, duplicate labels, empty unlabeled spaces, and bad-window cache summary.

`work_command_check` validates function availability after `work_reload`. It does not move windows, switch displays, or validate app presence.

Workspace layout commands may use `ws_recover_yabai_once` to restart yabai once when shared queries fail after normal retry or when a present app remains non-movable after activation/polling. The helper is cooldown-guarded so multiple failures in one run do not repeatedly restart yabai. Its restart boundary supports the loaded legacy `com.asmvik.yabai` LaunchAgent as well as yabai's standard service. Read-only commands are excluded through the shared recovery allowlist.

### Read-Only Workspace Observability

`workspace_snapshot` captures one immutable display, Space, and window snapshot through the shared bounded query helpers. `workspace_plan <workspace>` derives matched movable windows, fallback candidates, the target display and labeled Space, foreign-window contamination, and expected layout actions from that snapshot. `workspace_verify <workspace>` checks the same snapshot for label uniqueness, target-display ownership, managed-window placement, foreign windows, and semantic layout expectations. `workspace_verify --all` evaluates every configured observation contract against one shared snapshot and reports `satisfied`, `drift`, or `not_applicable`; `work_check` includes this summary without turning inactive or drifted observed workspaces into a fatal reload failure.

The first supported observation contracts are `gtd_meeting_wide` and `coding_control`, because recent failures involved their real window state rather than public command dispatch. Observation specs describe stable app aliases, selector shape, fallback eligibility, and final layout only. Existing module helpers remain the source of movement, activation, retry, and recovery behavior.

All three commands are strictly read-only. They do not activate or open apps, restart yabai, focus or move windows/Spaces, create or destroy Spaces, run cleanup, or apply display profiles. `workspace_plan` and `workspace_verify` omit window titles from their reports.

### Label-only Recovery

`workspace_restore_labels` handles the narrow case where owned windows and layout are already correct but yabai labels have disappeared. It defaults to dry-run and shares the observation contracts used by `workspace_plan` and `workspace_verify`.

A label is recoverable only when the owned or fallback candidate windows resolve to exactly one Space, that Space is on the contract display, it has no existing label, it contains no non-owned non-minimized windows, and no existing or duplicate workspace label conflicts with the operation. Ambiguous, contaminated, wrong-display, and already-conflicting states report an explicit `blocked_*` status.

`workspace_restore_labels --apply` performs only `yabai -m space <index> --label <label>`. It does not move or focus windows/Spaces, create or destroy Spaces, run cleanup, restart services, or apply a display profile. Multi-workspace apply is preflighted as one request: if any requested workspace is blocked, no label is written. Recovery is never invoked automatically from `yabairc`, Dock/yabai restart hooks, display profile application, or workspace entry commands.

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

- ``workspace_cleanup_mode_spaces <family> solo``
- ``workspace_cleanup_mode_spaces <family> wide``
- ``workspace_cleanup_mode_spaces <family> tall``

## GTD Ownership Rules

### ChatGPT

`ChatGPT` is shared by multiple workflows. The current global rule is:

**the last invoked module owns the `ChatGPT` window**

This keeps behavior deterministic without hidden precedence rules.

ChatGPT-owning workspaces capture a movable `ChatGPT` window through `workspace_capture_app_window`. If ChatGPT exists but yabai does not expose a movable window, the helper activates ChatGPT, polls for a refreshed movable window, retries the move once, and warns when yabai still cannot move it.

Wide/tall coding editor modes may own one already-open ChatGPT window as an optional helper. Wide places ChatGPT in the left third and VS Code in the right two thirds; tall places ChatGPT above VS Code. When ChatGPT is absent, VS Code uses the full workspace. Solo remains VS Code-only. All research modes may own one already-open Claude window as an optional helper.

`gtd_ai` owns ChatGPT when invoked directly. In `gtd_solo_all`, review runs after meeting so GTD review is the final SOLO owner for ChatGPT.

### Notes, Obsidian, And Dia

`Notes` is owned by `gtd_review_*` and by `gtd_ai` when the AI workspace is invoked.

`gtd_review_*` no longer requires Preview as the primary app. A review workspace is eligible when Preview, Notes, or ChatGPT is present. Wide and tall review are also eligible when one movable Obsidian window is present; solo review does not own Obsidian. Finder is still included when available, but Finder alone is intentionally not enough to create a review workspace because Finder is commonly present outside review work. Review collects existing Finder, Preview, Notes, and ChatGPT windows from the initial yabai snapshot before using refresh helpers, and only captures ChatGPT when an existing ChatGPT window does not land on the target. Wide and tall review select the first movable, non-minimized Obsidian window from that snapshot, include it in contamination ownership and fallback migrations, reconcile it onto the target Space, and apply its mode grid. They never launch Obsidian and never use its Space as a fallback target. If Obsidian is present but no movable window is available, the review step reports a warning and fails. When review owns Finder, Preview, or Notes, all movable windows for that app are moved to the review space, reconciled with up to three short retries if they remain on another Space, and receive the app's review grid.

Wide review uses a 2×16 grid: Finder occupies the left four columns at full height, Preview occupies the next six columns at full height, Obsidian occupies the upper-right six columns, and ChatGPT and Notes split the lower-right area into three columns each. Tall review uses a 4×2 grid: Preview occupies the top two rows at full width, Finder and Obsidian split the third row, and ChatGPT and Notes split the fourth row. When `gtd_ai` and wide/tall review share Obsidian, Notes, or ChatGPT, the last invoked workspace owns those windows.

When Notes is present but not exposed as a movable yabai window, `gtd_review_*` treats the current Notes space as the review target and moves Finder, movable Preview windows, and ChatGPT there. When Preview itself is present but not movable, the review target is focused and Preview bounds are applied through `workspace_apply_app_key_grid_bounds` instead of a yabai move. Movable Preview windows take precedence over unmovable Preview companion windows so an auxiliary unmovable window does not steal the review target. If Preview is reported movable but remains outside the target after the normal move and retry pass, review promotes Preview's current Space to the review fallback target, normalizes the review label there, evicts non-review windows, refreshes the window snapshot, and moves the current review windows onto that Space. If Preview is already on the target display but a different Space, review temporarily bounces Preview through another display before returning it to the focused review Space. This mirrors the mail workspace's primary-space fallback: the non-movable or failed-move app's space is moved to the requested display if it owns the target, the review label is normalized, movable non-review windows are evicted to an unlabeled holding space, and fallback app bounds are applied through the shared bounds helper. Review passes `--all-windows` for non-movable Preview and Notes bounds so the fallback does not only affect the largest scriptable window.

`Dia` is owned by `gtd_support_*`.

This avoids moving a single Notes window back and forth between support and review during aggregate entries.

### GTD Support Dia Layout

All GTD support modes collect every non-minimized, non-native-fullscreen Dia window that yabai reports as movable through `gtd_support_find_dia_windows`. Native fullscreen Dia windows are skipped so support layout does not move or grid a browser video fullscreen window. After the user leaves fullscreen, the next support run can collect that Dia window again.

If a previous support label points at a space mixed with non-Dia apps, `gtd_apply_support_space` retargets the label to a clean support space before moving Dia windows. If any non-fullscreen Dia window remains non-movable, even when other Dia windows are already movable, the helper activates Dia once, refreshes the window snapshot, uses shared `ws_recover_yabai_once` restart recovery, and fails closed with a warning unless every eligible Dia window becomes movable.

After the first support move, `gtd_apply_support_space` re-queries all currently movable non-native-fullscreen Dia windows and moves the whole set to the support target before applying layout. This keeps late-appearing Dia browser/tab windows with the support workspace without interfering with native fullscreen windows.

`gtd_support_layout_dia_windows` applies mode-specific layouts:

- solo: one full-screen; multiple Dia windows use a compact top/bottom or two-column grid
- wide: always uses left and right halves; the first half of the Dia windows stack top-to-bottom in the left half, and the remaining windows stack top-to-bottom in the right half
- tall: one bottom half; two top/bottom; three with two on top and one on bottom; four or more use a two-column grid

This multi-window policy is deliberately scoped to GTD support. Meeting and review workspaces keep app-specific selection rules until real failures justify broadening multi-window ownership.

### GTD AI

`gtd_ai` uses a single labeled Space, `gtd_ai`, across solo, wide, and tall layouts. The mode-specific entry points are `gtd_ai_solo`, `gtd_ai_wide`, and `gtd_ai_tall`; the convenience `gtd_ai` entry detects the current display mode and dispatches to one of those explicit entries.

The owned apps are ChatGPT, Obsidian, and Notes.

The AI workspace uses `workspace_retarget_contaminated_space` before preparing `gtd_ai`, so an old AI label mixed with unrelated apps is cleared and replaced with a clean target. Missing apps are opened when `gtd_ai_*` is invoked directly. If an app still has no movable layout window, the helper warns and skips that app instead of failing the whole workspace.

Layouts:

- wide: Notes left third, Obsidian middle third, ChatGPT right third
- tall: Notes top-left, Obsidian top-right, ChatGPT bottom half
- solo: Notes top-left, Obsidian top-right, ChatGPT bottom half

`gtd_ai` is intentionally not included in aggregate `work_*` entries because those entries should not launch the AI app set as a side effect of switching the whole display mode.

### Office ChatGPT And Documents

Office writing and slides workspaces use `office_apply_document_space` instead of the generic primary/helper flow. Word and PowerPoint are multi-window primary apps: all movable document windows are moved to the target workspace. ChatGPT remains a single shared helper window and follows the last-caller ownership rule.

Wide mode keeps ChatGPT in the left third when present. One document window uses the right two thirds; two document windows use the middle and right thirds; three or more document windows keep the first document in the middle third and split the right third between the next two document windows.

Tall mode keeps ChatGPT in the top half when there is one document window. With two document windows, ChatGPT and the first document share the top half left/right while the second document uses the bottom half. With three or more document windows, the bottom half is split between the second and third document windows.

### GTD Mail

GTD mail uses `workspace_apply_primary_helper_space` with Thunderbird as the required primary app and Outlook as an optional helper. If Thunderbird is missing, mail modes do not create a stale empty workspace. If Thunderbird remains non-movable, its current Space can become the mail workspace and Outlook is then captured onto that target when present.

Layouts:

- wide: Outlook left half, Thunderbird right half
- tall: Outlook top half, Thunderbird bottom half
- solo: Outlook top half, Thunderbird bottom half
- when Outlook is absent, Thunderbird uses the full target workspace

### GTD Meeting

`gtd_meeting_*` owns Zoom/zoom.us and Microsoft Teams/MSTeams only. Outlook belongs to GTD mail.

Zoom selection goes through `gtd_find_zoom_windows`, with `gtd_find_zoom_window` retained as the primary-window compatibility wrapper. The Zoom app key recognizes both `zoom.us` and `Zoom` because yabai may expose either name. Meeting capture includes movable Zoom main, meeting, video, share, and screen windows, while excluding mini windows. If Zoom is present but yabai has not exposed a movable window, the fallback path can activate Zoom once and re-query before giving up. In the normal movable path, every selected non-mini Zoom window receives the standard Zoom grid after final reconciliation so late meeting/video/share windows do not require a second shortcut run.

When visible Zoom remains present but non-movable after activation, `gtd_meeting_*` treats the current Zoom space as the meeting target. The Zoom space is moved to the requested display if needed, labeled as the meeting workspace, movable non-meeting windows are evicted to an unlabeled holding space, and Teams is moved there. When Zoom is present only as a hidden non-movable window, meeting applies Zoom's requested grid through System Events on the target display, re-queries yabai, and uses Zoom's resulting Space as the meeting target only if yabai confirms Zoom reached that display. This keeps hidden Zoom with the meeting without letting it steal SmartGit's fixed control Space.

Teams selection goes through `gtd_find_teams_windows`, with `gtd_find_teams_window` retained as the primary-window compatibility wrapper. It recognizes both `Microsoft Teams` and `MSTeams`, captures movable main, meeting, video, call, share, and screen windows, and excludes mini windows. Every returned Teams window receives the standard Teams grid after final reconciliation. If a non-movable Teams companion window is present and Zoom has not already provided a fallback target, the companion window's current Space becomes the meeting target and movable Zoom/Teams windows are moved there. This handles the `MSTeams` meeting window shape that yabai reports with no AX reference.

All `gtd_meeting_*` modes use `workspace_retarget_contaminated_space` before preparing the labeled space. If the existing meeting label points at a space that contains non-meeting apps, the label is cleared and a clean meeting space is selected instead of mixing the workflow into a contaminated space.

`gtd_meeting_solo`, `gtd_meeting_tall`, and `gtd_meeting_wide` retry captured Zoom/Teams moves when the first move does not place the captured meeting-window set on the target space. Zoom can also refresh once when no movable Zoom window was captured initially.

After the targeted retry paths, all `gtd_meeting_*` modes run a final Zoom/Teams reconciliation pass. That pass re-queries every currently movable Zoom and Teams window and moves the whole set to the meeting target, even when one window for that app is already on the target space. Zoom and Teams then get a short settle/re-query before layout, because meeting/video/call/share windows can appear just after the first all-window pass.

Expected meeting behavior:

- Zoom/zoom.us and Microsoft Teams/MSTeams remain together in GTD meeting spaces
- Outlook remains governed by GTD mail
- shared Zoom/Teams selection mechanics stay in `gtd_find_meeting_windows`
- Zoom-specific and Teams-specific wrapper policy stays in `gtd_find_zoom_windows` and `gtd_find_teams_windows`
- `gtd_meeting_wide` uses a left/right split: Zoom left, Teams right
- `gtd_meeting_tall` and `gtd_meeting_solo` use a top/bottom split: Zoom top, Teams bottom

### GTD Chat

The core GTD chat layout is:

- Keybase
- 钉钉
- WeChat
- Messages

WhatsApp is best-effort. Its window behavior is less stable in some sessions, so it should not make the whole chat workspace fragile.

FaceTime is an optional single-window chat app. When an existing movable FaceTime window is present, `gtd_chat` moves it to the chat Space and applies the same centered moderate-size bounds used for WhatsApp. It does not launch FaceTime when absent.

`gtd_chat` uses `workspace_retarget_contaminated_space` before preparing the labeled space. If an old `gtd_chat` label points at a space that also contains non-chat apps, such as Thunderbird or ChatGPT, the label is cleared and chat windows are moved to a clean chat space instead of preserving the mixed workspace.

`WeChat`, `Keybase`, `DingTalk`, `Messages`, and `FaceTime` are selected through `workspace_find_app_key_window` and retried once if they are missing from the final target space. This avoids silently skipping a movable chat window because of a stale bad-window cache entry, and gives DingTalk one activation/re-query path before reporting that yabai still cannot move it.

When DingTalk remains present but non-movable after activation, `gtd_chat` treats the current DingTalk space as the chat target. The DingTalk space is moved to the workspace primary display if needed, labeled as `gtd_chat`, movable non-chat windows are evicted to an unlabeled holding space, and WeChat, Keybase, Messages, WhatsApp, and FaceTime are moved there. DingTalk bounds use `workspace_apply_app_key_grid_bounds` in that fallback path because yabai cannot grid an unmovable window.

When Calendar remains present but non-movable, `gtd_calendar` treats the current Calendar space as the calendar target. The Calendar space is moved to the workspace primary display if needed, movable non-calendar windows are evicted to an unlabeled holding space, Reminders is moved there, and Calendar bounds are applied through `workspace_apply_app_key_grid_bounds`.

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

## Future Development Guardrails

New workspace code should preserve the current query and fallback boundary:

- do not call full `yabai -m query --displays`, `--spaces`, or `--windows` outside `common/ws_core.fish`; use `ws_query_displays`, `ws_query_spaces`, and `ws_query_windows`
- use `ws_focus_display` and `ws_focus_space` for focus operations; reserve `ws_query_current_display` and `ws_query_current_space` for callers that need current-focus data
- route app-name matching through app keys and shared selectors unless the module has a real special case such as Dia, Zoom, Teams, or Outlook
- when a present app is not movable, use `workspace_app_key_space_fallback_info` and `workspace_focus_space_fallback` before adding module-local fallback logic
- after moving required or multi-window app sets, re-query the target Space and fail or retry when the expected app did not land there
- use `--target-only` when confirming a moved app on a target Space so another same-app window cannot satisfy the check
- derive AppleScript/System Events bounds from `ws_query_displays`; do not open-code single-display yabai queries in bounds fallback code
- add focused `work_smoke` or `work_audit` coverage for every new retry, fallback, or multi-window ownership rule

These rules are specifically meant to avoid regressions where SmartGit, Zoom, Preview, or another non-movable app is detected but left on its original Space.

## Roadmap And TODO

The workspace system is currently structurally stable. Future work should be incremental, evidence-driven, and biased toward keeping public entry commands stable.

### Maintenance Backlog

#### Now

##### Verify Current Workspace Behavior In Daily Use

Watch:

- `work_solo`, `work_tall`, and `work_wide`
- `office_wide` and `office_tall` through the top-level external-display entries
- `gtd_mail_*` for Outlook helper placement with Thunderbird
- `gtd_meeting_*` for Zoom and Teams placement
- `gtd_support_*` for multiple Dia windows
- ChatGPT ownership when moving between coding wide/tall, GTD review, office, and GTD AI
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

If this remains stable, extract a small helper so tall and wide do not drift.

##### Watch Remaining Multi-Window Behavior

Review already moves all movable Finder and Preview windows together because real failures showed stray windows were being left behind. Before broadening other ownership, watch:

- whether multiple Outlook windows should move together in mail
- whether Zoom or Teams should ever avoid moving every meeting-related window
- whether ChatGPT should ever move as a multi-window set beyond the existing helper capture
- whether moving all same-app windows would steal windows from another active context

Do not generalize GTD support's Dia policy into broad multi-window ownership without concrete failures from real use.

##### Improve Diagnostic Summaries

The first summary step is complete: `workspace_verify --all` reports observed workspace state from one snapshot, and `work_check` prints the compact result without treating inactive workspaces as failures. `work_smoke_observability` provides a targeted regression entry for this layer.

Remaining possible improvements:

- compact one-line health summary
- clearer grouping for display-mode mismatches
- better separation of active vs historical warning signals

Recovery mechanics should remain explicit rather than automatic.

### Watchlist

##### ChatGPT Ownership

The current last-caller rule is acceptable for daily use. Future refinement may make ChatGPT capture behavior more explicit by distinguishing active capture from opportunistic inclusion.

##### Mail Outlook And Meeting Bad-Window Cache Behavior

Watch for:

- Outlook present in mail but `can_move=false` or `has_ax_reference=false`
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

#### Agreed Next-Version Implementation Plan

The next major workspace version should be implemented in documentation-first, read-only-first stages. The immediate goal is to make app, label, window-role, layout, and mode composition facts inspectable as data before using that data to move any windows. The snapshot/plan/verify prerequisite now exists for `gtd_meeting_wide` and `coding_control`; it remains separate from configured runtime movement.

Implementation order:

1. Add the initial configuration file and read-only helpers:
   - `.config/fish/functions/workspace/config/workspaces.json`
   - `workspace_config_check`
   - `workspace_config_get <workspace>`
   - `workspace_config_plan <workspace-or-mode>`
2. Add configuration validation to existing safety commands:
   - `work_smoke`
   - `work_doctor`
   - `work_inventory`
3. Migrate `coding_editor_wide` as the first configured runtime pilot while keeping its public command unchanged.
4. Expand by simple repeated families only after the pilot is stable in daily use:
   - `coding_editor_*`
   - `gtd_mail_*`
   - `office_writing_*`
   - `office_slides_*`
   - `research_*`
5. Keep ownership-sensitive and recovery-heavy workspaces fish-first until the configured runner has proven useful:
   - `gtd_meeting_*`
   - `gtd_review_*`
   - `gtd_support_*`
   - `gtd_chat`

Acceptance gates before any configured workspace is allowed to mutate state:

- `workspace_config_check` passes without warnings for the migrated workspace
- `workspace_config_plan <workspace>` shows the intended display role, label, app matches, layout, and cleanup
- `work_smoke` and `work_doctor` include the config check
- the public fish command still supports `--dry-run`
- `WORKSPACE_CONFIG_DISABLE=1` bypasses the configured path during migration
- missing required windows fail closed before creating, moving, relabeling, or destroying spaces

#### Configurable Workspace Definitions

This is the next major-version direction. The current fish-based implementation should remain the stable runtime until the configured runner has read-only checks, dry-run output, and at least one migrated workspace passing daily use.

The goal is to move app, space, and layout facts into data while keeping behavior, recovery, and safety in fish helpers. This should reduce repeated module code without turning the workspace system into a generic workflow engine.

Public command entry points should remain recognizable. Users should still run `coding_control`, `gtd_meeting_tall`, `work_wide`, or skhd bindings; those commands may internally call a configured runner later. During migration, a thin fish wrapper may still exist for each public command, but it should only name a configured workspace or mode.

##### Configuration Boundary

The configuration layer should own stable facts:

- app aliases and accepted macOS app names
- workspace ids and labels
- target display role: `primary`, `external`, `wide`, `tall`, or `auto_external`
- space layout such as `float`
- required and optional window roles
- selector policy for each window role
- layout actions for each window role
- mode composition, such as which workspace ids belong to `gtd_wide`
- simple cleanup policy by family and mode

The fish runtime should continue to own behavior:

- display UUID discovery and primary-display persistence
- display profile application
- yabai and jq invocation, timeout handling, and retries
- app-specific recovery, such as Outlook reopen behavior
- bad-window cache mechanics
- labeled-space creation, retargeting, and cleanup mechanics
- actual window movement, confirmation, and diagnostics

Do not put shell commands, raw jq filters, loops, conditionals, or arbitrary fallback chains in JSON.

##### File Layout

Start with one config file to avoid spreading data too early:

```text
.config/fish/functions/workspace/config/workspaces.json
```

Keep the schema documented here first. Add a separate JSON schema file only if validation grows beyond a small jq/fish checker.

If the single file becomes hard to review later, split in this order:

1. `apps.json`
2. `layouts.json`
3. `workspaces.json`
4. `modes.json`

##### Version 1 Shape

The first runtime-compatible shape should stay deliberately small:

```json
{
  "version": 1,
  "apps": {
    "code": {
      "names": ["Code", "Visual Studio Code"]
    },
    "claude": {
      "names": ["Claude"]
    }
  },
  "layouts": {
    "coding_editor_wide": [
      {
        "role": "primary",
        "grid": "1:3:1:0:2:1"
      },
      {
        "role": "helper",
        "grid": "1:3:0:0:1:1"
      }
    ],
    "single_full": [
      {
        "role": "primary",
        "grid": "1:1:0:0:1:1"
      }
    }
  },
  "workspaces": {
    "coding_editor_wide": {
      "label": "coding_editor_wide",
      "display_role": "wide",
      "space_layout": "float",
      "windows": [
        {
          "role": "primary",
          "app_key": "code",
          "required": true,
          "movable": true
        },
        {
          "role": "helper",
          "app_key": "claude",
          "required": false,
          "movable": true
        }
      ],
      "layout_ref": "coding_editor_wide",
      "primary_alone_layout_ref": "single_full",
      "cleanup": {
        "family": "coding",
        "opposite_modes": ["solo", "tall"]
      }
    }
  },
  "modes": {
    "coding_wide": ["coding_editor_wide"],
    "work_wide": ["gtd_wide", "coding_wide", "office_wide", "research_wide"]
  }
}
```

Prefer `grid` layouts for external WIDE/TALL workspaces because external monitors vary by size. Keep pixel-level `move_abs` and `resize_abs` as an escape hatch for primary-display fixed workspaces such as `coding_control`, and migrate those only after fractional/grid layouts have proven insufficient.

Selectors should remain explainable:

- exact app name through `app_key`
- optional app name regex only when exact names are not enough
- optional title include or exclude strings
- `movable`
- visible windows only
- non-empty title when needed

Each workspace should have a single explicit label. Config should never infer labels from command names at runtime.

##### Runtime Runner

The configured runner should be a deterministic adapter from data to existing helpers. Recommended phases:

1. Load and validate the config version.
2. Resolve the requested workspace or mode id.
3. Resolve the target display role through existing display-role helpers.
4. Query current windows once, then run configured selectors against that snapshot.
5. Fail closed when required windows are missing.
6. Prepare the labeled space only after config and required-window checks pass.
7. Move selected windows to the labeled space and re-query to confirm final ownership.
8. Apply layout actions.
9. Run configured cleanup specs.
10. Print concise status or debug output.

The runner should support:

- `workspace_config_check`
- `workspace_config_get <workspace>`
- `workspace_config_plan <workspace-or-mode>`
- `workspace_run_configured <workspace>`
- `workspace_run_configured_mode <mode>`
- `--dry-run` for every configured movement path

`workspace_config_plan` and `--dry-run` must not create spaces, move windows, apply display profiles, or destroy spaces. They should print the display role, label, matched windows, missing required windows, layout actions, and cleanup actions that would run.

##### Migration Stages

1. **Schema and read-only validation**
   Add `workspaces.json`, `workspace_config_check`, `workspace_config_get`, and `workspace_config_plan`.
   Include config validation in `work_smoke` and `work_doctor`.

2. **Read-only inventory comparison**
   Add `work_inventory` output for configured apps, workspaces, modes, and unmigrated fish-only entries.
   This should make drift visible before behavior changes.

3. **Migrate the simplest repeated entry first**
   Start with `coding_editor_wide`. It uses the shared primary/helper path with required VS Code, optional ChatGPT, grid-only layout, and no Space fallback policy. Keep the public command name unchanged. The pilot must preserve the full-workspace VS Code fallback when ChatGPT is absent before expanding to other optional-helper families.

4. **Migrate simple families by pattern**
   Candidate command families:
   - `coding_editor_*`
   - `gtd_mail_*`
   - `office_writing_*`
   - `office_slides_*`
   - `research_*`

5. **Migrate absolute-layout primary workspaces**
   Move `coding_control` after the grid-based pilot is stable.
   Use this stage to decide whether `move_abs` and `resize_abs` are still needed or whether a ratio-based frame layout is enough.

6. **Evaluate GTD meeting after simple modules**
   `gtd_meeting_*` may use configured final layout later, but meeting-app recovery should remain in fish helpers such as `gtd_find_meeting_window`, `gtd_find_zoom_windows`, and `gtd_find_teams_windows`.

7. **Leave ownership-sensitive modules until last**
   Keep these fish-first until there is strong evidence that config reduces complexity:
   - `gtd_chat`
   - `gtd_review_*`
   - `gtd_support_*`
   - any shared-app workspace where the last invoked module owns an app window

Non-goals:

- do not configure display UUID resolution
- do not configure bad-window cache mechanics
- do not configure raw yabai timeout behavior
- do not encode complex app recovery logic directly in JSON; config should name the app and policy, while fish helpers implement recovery
- do not replace public fish entry commands such as `coding_control`, `gtd_meeting_tall`, or `work_tall`
- do not support arbitrary jq expressions, conditionals, loops, or fallback chains in JSON
- do not migrate Outlook, Dia, WhatsApp, or other special recovery behavior into config in the first version

Likely helper set:

- `workspace_config_check`
- `workspace_config_get <workspace>`
- `workspace_config_plan <workspace-or-mode>`
- `workspace_select_configured_windows <workspace>`
- `workspace_prepare_configured_space <workspace>`
- `workspace_apply_configured_layout <workspace>`
- `workspace_run_configured <workspace>`
- `workspace_run_configured_mode <mode>`

Technical guardrails:

- fail closed on missing config, invalid schema, jq failure, display query failure, or missing required windows
- do not create spaces or move windows when config validation fails
- keep selectors explainable; exact app, app regex, title exclusion, movable, visible, and non-empty title are enough for the first version
- keep layouts simple; `grid`, `move_abs`, and `resize_abs` are enough for the first version
- prefer shared layout refs over copy-pasted geometry
- make every configured command runnable with `--dry-run`
- add `WORKSPACE_DEBUG_CONFIG=1` for selected workspace name, selector result, window id, and applied position
- keep an emergency bypass such as `WORKSPACE_CONFIG_DISABLE=1` during migration
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

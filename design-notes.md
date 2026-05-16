# Workspace Design Notes

## Design Goals

The workspace system is designed around four goals:

1. predictable space labeling and reuse
2. minimal stale-space accumulation
3. portable cross-machine behavior
4. consistent layout semantics across modules

The system is modular so that GTD, coding, office, and research workflows can evolve independently while still sharing a common operational model.

## Why Internal Display UUID Was Decoupled

Earlier versions hardcoded the internal display UUID directly inside multiple workspace functions. That made migration to a new machine inconvenient because the same UUID had to be edited in many files.

The current design removes machine-specific UUID constants from business-level workspace functions and stores the internal display UUID once through a fish universal variable. The helper functions `get_internal_display_uuid`, `resolve_internal_display`, and `resolve_external_display` provide a single indirection layer that makes the system portable.

This reduces migration cost to a single setup command on a new machine.

The operational setup command is:

```fish
detect_and_set_internal_display_uuid
```

If detection is ambiguous, the manual setup command is:

```fish
set_internal_display_uuid <internal-display-uuid>
```

The stored value should be checked with:

```fish
get_internal_display_uuid
```

This value is important because it defines the display roles used by the whole workspace system:

- `resolve_internal_display` uses it to anchor internal fixed workspaces.
- `resolve_external_display` uses it to choose the non-internal display for WIDE and TALL task workspaces.
- `display_apply_solo`, `work_solo`, `work_wide`, and `work_tall` all assume this role mapping is correct.

If the UUID is missing or wrong, the visible symptom is usually not a shell error. The more likely failure mode is that windows move to the wrong display or external layouts fall back to the internal screen.

## Why Display Resolution Was Further Unified

After the UUID decoupling step, many workspace functions still retained transitional display-selection logic based on:

- `get_internal_display_uuid`
- `resolve_target_display`
- direct display enumeration through `yabai -m query --displays`

That transitional form has now been further simplified.

The current rule is:

- internal fixed workspaces use `resolve_internal_display`
- external task workspaces use `resolve_external_display`

This means business-level workspace functions no longer need to know how internal and external displays are resolved. That logic now lives in the common helper layer.

This change reduces repeated display-selection boilerplate, improves readability, and keeps future display-policy changes localized to shared helpers rather than scattered across module functions.

## Why Display Profiles and Workspace Recovery Are Separate

The display layer and the workspace layer now have distinct responsibilities.

Display-profile functions such as:

- `display_wide_left`
- `display_tall_left`

are responsible only for monitor geometry and arrangement. They mainly apply `displayplacer` profiles and remain tied to specific physical monitor setups.

Workspace recovery is a separate concern. After a display topology change, the workspace system must be reloaded and the target mode must be re-entered. This is now represented by the `display_apply_*` layer, such as:

- `display_apply_wide_left`
- `display_apply_tall_left`
- `display_apply_solo`

These functions apply the display profile and then run:

- `display_reload`
- `work_reload`

They do not automatically force the final workspace mode. The user may then explicitly run:

- `work_wide`
- `work_tall`
- `work_solo`
- or a specific module entry such as `coding_wide` or `gtd_review_wide`

This keeps display setup and workspace intent clearly separated.

## Why Labeled and Unlabeled Space Cleanup Are Separate

The system distinguishes between two different cleanup responsibilities.

`cleanup_unlabeled_empty_spaces` handles empty spaces that do not carry structural meaning. These are usually transient or accidental spaces created during window movement or space creation.

Module-specific cleanup functions such as `gtd_cleanup_wide_spaces` or `research_cleanup_tall_spaces` handle empty spaces that still carry valid labels. These are structured workspaces that have become empty after mode switching or app disappearance.

Keeping these two cleanup mechanisms separate reduces the risk of deleting meaningful workspaces too aggressively while still keeping the space graph tidy.

## Why Space Creation Now Uses Explicit Post-Creation Relocation

A key issue was identified during monitor switching tests.

In the current environment, `yabai -m space --create` does not reliably create a new space directly on the intended target display, even after focusing the target display or a space on that display first.

Because of this, the old assumption that display focus would control space creation destination is no longer used.

The current strategy in `find_or_create_labeled_space` is:

1. create the new space
2. identify the newly created space by UUID difference
3. check which display it was actually created on
4. explicitly move it to the target display if necessary

This change is the key fix that made external wide workspaces recover correctly after switching between solo mode and different external monitors.

## Why Label Ownership Is Normalized Explicitly

A second issue observed during display switching was stale label carryover.

When a workspace was recreated on a different display, the same label could still remain attached to an older space. This produced ambiguous label ownership and made workspace state harder to reason about.

`prepare_labeled_space` now clears the same label from any other space before assigning it to the target space.

This keeps workspace labels unique, explicit, and stable across display transitions.

## Why ChatGPT Uses Last-Caller Ownership

`ChatGPT` is used in multiple workspace modules as a helper window. Because it is currently treated as a shared single-instance application, simultaneous persistent ownership by multiple modules is not feasible.

The chosen rule is simple:

**the last invoked module owns the `ChatGPT` window**

This rule keeps the system deterministic and avoids hidden precedence logic between modules. It also reflects the fact that `ChatGPT` is usually needed in the current foreground workflow rather than in every module at once.

## Why Primary-App Absence Destroys Stale Empty Spaces

Some workspaces are defined around a required primary application:

- Word for office writing
- PowerPoint for office slides
- Zotero for research
- Code for coding editor
- Thunderbird for GTD mail

If the primary application is unavailable, retaining an empty labeled space usually provides no value and instead creates stale structural residue. For that reason, workspace functions destroy an existing empty labeled space with the same label before returning.

This policy keeps workspace status views accurate and reduces manual cleanup.

## Why WhatsApp Is Best-Effort in gtd_chat

The GTD chat workspace is primarily defined by a stable four-window layout:

- Keybase
- 钉钉
- WeChat
- Messages

`WhatsApp` is useful when available, but its window behavior can be less stable in some sessions. To avoid making the entire chat workspace fragile, `WhatsApp` is treated as best-effort rather than a strict layout dependency.

This keeps `gtd_chat` robust while still allowing optional inclusion of `WhatsApp` where possible.

## GTD Notes Ownership

`Notes` is owned by `gtd_review_*`.

`gtd_support_*` only manages `Dia`. This avoids moving a single `Notes` window back and forth between `gtd_support_*` and `gtd_review_*` when running aggregate entries such as `gtd_tall`, `gtd_wide`, `work_tall`, or `work_wide`.

The current GTD support rule is:

- `gtd_support_tall`: `Dia` full-size on the support workspace
- `gtd_support_wide`: `Dia` full-size on the support workspace

## Display Mode Entries

The workspace system currently has three top-level display/work modes:

- `display_apply_solo; work_solo`: single internal display
- `display_apply_wide_left; work_wide`: internal display plus wide external display
- `display_apply_tall_left; work_tall`: internal display plus tall external display

As of Phase 4, `work_solo` arranges the current first batch of solo workspaces:

- `coding_solo`
- `research_solo`
- `gtd_solo_all`

The current first-batch module solo entries are:

- `coding_solo`: `Code` left 2/3, visible `ChatGPT` right 1/3, plus `coding_control`
- `research_solo`: `Zotero` left 2/3, visible `ChatGPT` right 1/3
- `gtd_support_solo`: `Dia` full screen
- `gtd_review_solo`: `Finder`, `Preview`, visible `ChatGPT`, and `Notes`
- `gtd_mail_solo`: `Thunderbird` full screen
- `gtd_meeting_solo`: `Zoom`, `Teams`, and `Outlook`

Office solo entries are intentionally deferred.

## Three-Mode Cleanup

Phase 5 extends cleanup and status handling to the three active display/work modes:

- `solo`
- `wide`
- `tall`

Each module family that currently has solo entries now has a matching cleanup helper:

- `coding_cleanup_solo_spaces`
- `research_cleanup_solo_spaces`
- `gtd_cleanup_solo_spaces`

Wide and tall entries clean empty solo spaces in addition to the opposite external mode. Solo entries already clean empty wide and tall spaces. Cleanup remains conservative: only empty labeled spaces are destroyed.

Mode status output now includes a solo section for each family, including office, even though office solo entries are still deferred.

## Cleanup Abstraction

Phase 6 starts with the lowest-risk abstraction: labeled empty-space cleanup.

The shared helper is:

- `cleanup_labeled_empty_spaces`

It destroys empty spaces whose labels match a caller-provided regular expression. Module-specific cleanup functions remain as thin wrappers, for example:

- `coding_cleanup_wide_spaces`
- `coding_cleanup_tall_spaces`
- `coding_cleanup_solo_spaces`
- `gtd_cleanup_wide_spaces`
- `gtd_cleanup_tall_spaces`
- `gtd_cleanup_solo_spaces`
- `research_cleanup_wide_spaces`
- `research_cleanup_tall_spaces`
- `research_cleanup_solo_spaces`
- `office_cleanup_wide_spaces`
- `office_cleanup_tall_spaces`
- `office_cleanup_solo_spaces`

The second cleanup abstraction is:

- `destroy_empty_labeled_space`

It centralizes the repeated primary-app absence path. When a module's primary app is unavailable, the module can destroy the first empty space with that exact label before returning. This intentionally preserves the earlier conservative behavior: it does not delete occupied spaces and it does not delete every matching labeled space.

The third abstraction is:

- `ws_find_window`

It centralizes simple exact-app window selection from `yabai -m query --windows` JSON. The helper supports the recurring filters used by editor/research workspaces:

- non-minimized windows only
- optional visible-window requirement
- optional exact target space

Phase 6 initially applies this only to `coding_editor_*` and `research_*`, where the old jq expressions were direct equivalents. GTD and office modules keep their local app-specific selection logic until those rules are reviewed separately.

This helper now also covers the reviewed GTD and office selection rules. It supports the extra filters needed there:

- app-name regular expressions for apps such as `DingTalk` / `钉钉` and `WhatsApp`
- non-empty title preference for apps such as `Dia` and `Notes`
- title-exclusion filters for apps such as `Zoom` and `Teams`

The fourth abstraction is:

- `ws_move_app_pair_to_space`

It centralizes the common two-window move flow used by editor/research workspaces:

- move the primary app window to the target space
- move the helper app window to the target space when present
- focus the target space

It deliberately does not apply layout grids and does not perform final capture. Those stay in the module functions because the layout meaning differs between coding, research, solo, wide, and tall modes.

The matching single-window abstraction is:

- `ws_move_app_to_space`

It is used where a workspace is centered around one movable app window, such as GTD mail and GTD support. Multi-window GTD modules still keep their explicit move order locally, but their window selection now uses `ws_find_window`.

The matching multi-window abstraction is:

- `ws_move_windows_to_space`

It moves a caller-provided list of window ids to a target space and then refocuses the target space only when at least one valid window id was provided. This is used by GTD review, meeting, and calendar modules to keep their local selection/layout rules while avoiding repeated empty move/focus/sleep blocks.

## Batch Cleanup Suppression

Aggregate entries such as `gtd_tall`, `gtd_wide`, `coding_tall`, `coding_wide`, `office_tall`, and `office_wide` own their mode-level labeled cleanup. They clean opposite-mode empty labeled spaces before and after calling their child module functions.

During those child module calls, the aggregate entry sets:

- `WORKSPACE_SKIP_LABELED_CLEANUP=1`

`cleanup_labeled_empty_spaces` treats that flag as a no-op. This keeps standalone module behavior unchanged while avoiding repeated labeled-space scans and destroy attempts inside aggregate runs such as `work_tall`.

This keeps call sites readable while removing duplicated `yabai -m query --spaces | jq ... | yabai -m space --destroy` logic.

Window capture and layout logic remains explicit in each workspace function for now. Window move helpers intentionally move only caller-provided window IDs; they do not rediscover other same-app windows during the move step because stale yabai window IDs can block for seconds.

## Phase 7 Performance Closure

Phase 7 focused on making repeated WIDE, TALL, and SOLO transitions fast and predictable when yabai reports stale or slow window IDs.

The final rules from this phase are:

- `ws_window` is the only supported wrapper for direct `yabai -m window ...` calls.
- `ws_window` uses a bounded yabai timeout. The default is `1` second and can be overridden with `WORKSPACE_YABAI_TIMEOUT_SECONDS`.
- Window IDs that time out or hit the alarm path are cached under `/tmp/workspace-ws-window-bad`.
- Bad-window cache entries are kept for `600` seconds by default and can be overridden with `WORKSPACE_BAD_WINDOW_TTL_SECONDS`.
- `ws_find_window` skips known bad window IDs, so later module captures do not repeatedly choose a stale ID.
- Move helpers move only the window IDs captured by the caller. They do not perform a second `--not-space` discovery pass.
- `WORKSPACE_DEBUG_WINDOW=1` remains the profiling switch for slow window actions and cache skips.

The removed retry-discovery behavior was intentionally conservative for correctness, but it became harmful in practice: when yabai returned stale IDs, the retry pass often rediscovered another bad same-app window and multiplied the delay across aggregate commands such as `gtd_tall_all`, `work_tall`, and `work_solo`.

The current tested performance target is:

- aggregate commands should finish in a few seconds when the target applications already exist
- a newly encountered stale window should add at most the configured timeout once
- repeated commands should skip known bad windows until the cache expires

Non-window yabai operations use a separate bounded wrapper:

- `ws_yabai` is the supported wrapper for shared `yabai -m query`, `space`, and `display` calls.
- `ws_query_windows` is the supported helper for module-level full-window captures.
- `WORKSPACE_YABAI_COMMAND_TIMEOUT_SECONDS` controls this timeout and defaults to `5` seconds.
- `WORKSPACE_DEBUG_YABAI=1` prints slow or failed shared yabai calls.
- Workspace commands must fail closed when an initial yabai query cannot return reliable JSON. They should not treat an empty timeout result as "no matching apps" or as a valid empty space list.
- Space creation must compare UUIDs only after a successful pre-create and post-create space snapshot.

The latest local verification after Phase 7 showed:

- `gtd_tall_all`: sub-second after bad-window filtering
- `work_tall`: about 2.5 seconds
- `work_solo`: about 1.6 seconds

These timings depend on the live yabai/app state, but they confirm that the previous multi-minute outliers are no longer expected under normal repeated use.

## Phase 8 Diagnostics Closure

Phase 8 adds a read-only diagnostics layer so display transitions can be inspected before any recovery command is introduced.

The new command is:

- `work_diagnostics`

It reports:

- display summary and current focused display/space
- all labeled workspace spaces grouped by label
- empty labeled spaces
- duplicate labels
- empty unlabeled spaces
- bad-window cache entries from `/tmp/workspace-ws-window-bad`

`work_check` now runs:

1. module reload
2. `work_diagnostics`
3. mode status for GTD, coding, office, and research

`work_status` also starts with `work_diagnostics` before printing the fuller module status snapshots.

Phase 8 intentionally does not add automatic recovery. The current rule is:

- diagnose first
- keep recovery manual until the output has been tested through real SOLO, WIDE, and TALL display transitions

Recommended manual checks are:

```fish
work_reload
work_diagnostics
work_check
```

After changing display state, run:

```fish
display_apply_solo
work_solo
work_diagnostics
```

or:

```fish
display_apply_tall_left
work_tall
work_diagnostics
```

The expected result is not necessarily zero empty spaces at all times. The useful signal is whether stale labels, duplicate labels, empty labeled spaces, and bad-window cache entries are visible and easy to interpret.

## Phase 8.5 Light Recovery Closure

Phase 8.5 adds manual recovery commands that act only on diagnostic artifacts:

- `work_bad_windows`
- `work_clear_bad_windows`
- `work_cleanup_empty_labeled_spaces`
- `work_cleanup_empty_unlabeled_spaces`
- `work_recover_light`

The recovery boundary is intentionally narrow:

- bad-window cache cleanup is limited to `/tmp/workspace-ws-window-bad`
- labeled-space cleanup is limited to empty spaces whose labels match known workspace label patterns
- unlabeled-space cleanup keeps the current space protected
- no command in this phase moves application windows
- no command in this phase applies a layout or display profile

This phase closes the loop from diagnosis to conservative manual repair:

```fish
work_diagnostics
work_recover_light
work_diagnostics
```

The recovery command is deliberately not called automatically by `work_check`. `work_check` remains a reporting tool, while `work_recover_light` is an explicit user action.

## Phase 9 Documentation Closure

Phase 9 consolidates user-facing documentation without changing runtime behavior.

The current documentation split is:

- `workspace/README.md`: operational commands for new-machine setup, daily use, diagnostics, recovery, modes, reloads, and status checks
- `workspace/design-notes.md`: design rationale, phase history, rules, maintenance strategy, and future TODOs
- `skhd/README.md`: concrete hotkey table and active binding source
- `skhd/design-notes.md`: hotkey design rationale

The Phase 9 documentation rules are:

- put commands a user is expected to run in `README.md`
- put reasoning and tradeoffs in `design-notes.md`
- keep `skhd` docs aligned with the actual `skhdrc`
- keep GTD ownership text consistent: `gtd_support_*` owns `Dia`, while `gtd_review_*` owns `Notes`
- keep recovery documentation explicit that `work_recover_light` does not move windows or apply layouts
- keep internal display UUID setup visible as a new-machine bootstrap step

## Phase 10.1 Reload Source Closure

Phase 10.1 reduces reload/source duplication without changing workspace layout behavior.

The shared common-helper source list now lives in:

- `workspace/common/source_workspace_common.fish`

`work_reload` sources common helpers once, then loads display and module reloaders. While `work_reload` calls nested module reloaders, it sets:

- `WORKSPACE_SKIP_COMMON_RELOAD=1`

Module reloaders respect that flag and skip re-sourcing common helpers during nested reloads. When a module reloader such as `gtd_reload`, `coding_reload`, `office_reload`, or `research_reload` is run directly, it still sources common helpers itself.

The active shell startup entry is now intentionally small:

```fish
source ~/.config/fish/functions/workspace/common/work_reload.fish
work_reload
```

This keeps shell startup, full reload, and standalone module reload behavior consistent while avoiding repeated common-helper source blocks across files.

## Phase 10.2 Status Output Closure

Phase 10.2 standardizes status output without changing workspace layout behavior.

The shared status helpers are:

- `workspace_status_snapshot`
- `workspace_mode_status_section`

`workspace_status_snapshot` prints the common display and space fields:

- display index, uuid, frame, focus, space count, spaces
- space index, label, display, window count, windows

`workspace_mode_status_section` prints a titled labeled-space section for a caller-provided label regex. Module mode-status functions now use it for solo, wide, tall, and internal sections.

Standalone module status commands such as `gtd_status` and `coding_status` still print a full display/space snapshot plus their app-specific windows.

`work_status` prints:

1. `work_diagnostics`
2. one shared workspace snapshot
3. module app sections

While `work_status` calls module status functions, it sets:

- `WORKSPACE_SKIP_STATUS_SNAPSHOT=1`

This prevents four repeated display/space snapshots in the combined output. The flag is restored after `work_status` finishes.

## Phase 10.3 Cleanup Wrapper Closure

Phase 10.3 standardizes cleanup wrapper patterns without changing layout behavior.

The cleanup wrapper rule is:

- module-specific cleanup functions remain thin wrappers around `cleanup_labeled_empty_spaces`
- mode-specific wrappers use the same mode vocabulary: `solo`, `wide`, `tall`
- cleanup remains conservative and only destroys empty labeled spaces
- broad recovery cleanup is still explicit through `work_cleanup_empty_labeled_spaces` or `work_recover_light`

The research label regex now uses:

```text
^research(_.*)?_<mode>$
```

This intentionally matches both current labels such as `research_wide` and possible future labels such as `research_notes_wide`, while avoiding looser matches like `researchfoo_wide`.

The global workspace labeled cleanup pattern now includes:

- `coding_.*_(solo|wide|tall)`
- `coding_control`
- `gtd_.*_(solo|wide|tall)`
- `gtd_chat`
- `gtd_calendar`
- `office_.*_(solo|wide|tall)`
- `research(_.*)?_(solo|wide|tall)`

`office_cleanup_solo_spaces` exists for consistency with the mode/status vocabulary, even though office solo workspace entries are still deferred.

## Phase 10.4 Layout Duplication Review

Phase 10.4 reviews duplicated module layout code and intentionally does not extract a broad layout abstraction yet.

The repeated structure across many workspace functions is:

1. clean opposite-mode empty spaces
2. find the primary required window
3. resolve the target display
4. find or create the labeled space
5. prepare the labeled space
6. move captured windows
7. re-capture windows on the target space
8. apply a mode-specific grid layout
9. focus the target space and clean unlabeled empty spaces

The strongest duplication candidates are:

- `coding_editor_wide` / `coding_editor_tall`
- `research_wide` / `research_tall`
- `office_writing_wide` / `office_writing_tall`
- `office_slides_wide` / `office_slides_tall`
- `gtd_mail_wide` / `gtd_mail_tall`

These pairs mostly differ by:

- label
- opposite-mode cleanup function
- final grid geometry
- short user-facing comments

The higher-risk candidates are:

- `gtd_review_wide` / `gtd_review_tall`
- `gtd_meeting_wide` / `gtd_meeting_tall`
- `gtd_support_wide` / `gtd_support_tall`
- `coding_control`
- `gtd_chat`
- `gtd_calendar`

These functions contain more workflow-specific window selection, optional-window handling, fixed internal-display behavior, title filters, or absolute positioning.

Current decision:

- keep layout functions explicit for now
- do not introduce a generic "workspace layout engine"
- only consider small helpers when they remove boilerplate without hiding app ownership or layout geometry

Future low-risk helper candidates:

- a helper for "required primary window missing: destroy empty labeled space and return"
- a helper for "external two-window workspace with caller-provided grid specs"
- a helper for "final on-space capture for primary/helper app pair"

These should be introduced one at a time and only with before/after tests for the affected module pair.

## Phase 11 Command Entry Check

Phase 11 adds a read-only command availability check:

- `work_command_check`

It verifies that documented workspace commands, display commands, status commands, recovery commands, and hotkey entry points are loaded after `work_reload`.

This check is intentionally limited to function availability. It does not execute layout commands, move windows, switch displays, or validate app presence.

Recommended use:

```fish
work_reload
work_command_check
```

This protects against documentation and source-loading drift, especially after adding new entry points or changing reload/source structure.

## Current Operational State

The current workspace system has now reached a more stable post-fix state.

The following points have been verified:

- `coding_editor_wide`
- `research_wide`
- `gtd_meeting_wide`
- `gtd_support_wide`
- `gtd_review_wide`
- `gtd_mail_wide`

can all be correctly recreated on the external display after re-running the corresponding workspace commands.

The key common-layer fixes from this round are now concentrated in:

- `workspace/common/find_or_create_labeled_space.fish`
- `workspace/common/prepare_labeled_space.fish`
- `workspace/common/cleanup_unlabeled_empty_spaces.fish`

At present, the major correctness issue has been resolved. The remaining issues are mostly cleanup and maintenance refinements rather than structural failures.

## Maintenance Strategy

The current maintenance strategy is:

1. add reusable mechanics only in `workspace/common`
2. keep module-level workspace behavior explicit and readable
3. prefer small local fixes over broad hidden abstractions
4. treat display profile changes and workspace recovery as separate layers
5. use `*_reload` commands as the standard post-edit validation step
6. use `*_mode_status` and `*_status` for regression checking
7. use `work_check` as the lightweight full-system regression entry point after structural edits
8. use `work_diagnostics` before recovery
9. use `work_recover_light` only as an explicit manual recovery action

The system is now considered structurally stable. Future changes should focus on incremental behavioral refinement rather than broad architectural rewrites.

## Current Recommended Usage After Display Switching

When switching to a solo internal-display configuration, the current recommended sequence is:

```fish
display_apply_solo
work_solo
work_diagnostics
```

When switching to a wide-left external monitor configuration, the current recommended sequence is:

```fish
display_apply_wide_left
work_wide
work_diagnostics
```

When switching to a tall-left external monitor configuration, the current recommended sequence is:

```fish
display_apply_tall_left
work_tall
work_diagnostics
```

If the user does not want to enter the full work mode immediately, the display and reload phase can be run first:

```fish
display_apply_wide_left
```

and then followed manually by any specific module entry such as:

- `coding_wide`
- `research_wide`
- `gtd_meeting_wide`
- `gtd_review_wide`

This is the current recommended operational pattern.

If diagnostics show only empty workspace spaces or bad-window cache entries, the conservative manual recovery command is:

```fish
work_recover_light
```

This command does not move windows, apply layouts, or switch display profiles.

## Phase 12 GTD Meeting Stability

Phase 12 closes the Outlook-specific GTD meeting issue where yabai can expose a `Microsoft Outlook` window that is not movable and has no AX reference.

Rules added in this phase:

- `ws_find_window --movable` filters candidate windows to `can-move=true`.
- `gtd_find_outlook_window` only returns movable Outlook windows.
- If Outlook exists but no movable Outlook window is available, meeting commands warn instead of pretending Outlook was moved.
- `gtd_reopen_outlook` is a light manual recovery command: it clears Outlook bad-window cache entries, activates/reopens Outlook, and prints Outlook window diagnostics.
- `gtd_apps` reports `can_move`, `can_resize`, `has_ax_reference`, and `bad_window_cached` so Outlook AX/yabai state can be diagnosed without ad hoc jq commands.

## TODO List

### 1. Refine ChatGPT ownership handling

The current global rule is intentionally simple:

**the last invoked module owns the `ChatGPT` window**

This rule is acceptable for daily use, but future refinement may improve code clarity by making ChatGPT capture behavior more explicit. Possible directions include:

- defining which workspace functions actively capture ChatGPT
- defining which functions only include ChatGPT opportunistically
- introducing a small shared helper for optional ChatGPT capture

This is not a correctness issue. It is a future maintainability improvement.

**Estimated effort:** small to medium  
**Affected files:** all workspace functions that currently capture `ChatGPT`

### 2. Improve WhatsApp compatibility in `gtd_chat`

`gtd_chat` currently treats `WhatsApp` as best-effort rather than as a strict layout dependency.

This is acceptable for current usage, but future improvements may include:

- more robust window identification
- better handling for non-standard or non-movable WhatsApp windows
- a clearer separation between core chat layout and optional satellite windows

The current four-window core remains:

- `Keybase`
- `钉钉`
- `WeChat`
- `Messages`

**Estimated effort:** small  
**Affected files:** `workspace/gtd/internal/gtd_chat.fish`, related notes in documentation

### 3. Continue improving diagnostic summaries

The current top-level workspace layer already includes:

- `work_reload`
- `work_status`
- `work_mode_status`
- `work_diagnostics`
- `work_bad_windows`
- `work_recover_light`
- `work_solo`
- `work_wide`
- `work_tall`
- `work_check`

A future refinement may improve the presentation of this layer by adding:

- stronger summary output in `work_check`
- a compact one-line health summary
- clearer grouping for display-mode mismatches
- optional warnings when a configured internal display UUID is not present

The recovery mechanics themselves are already intentionally conservative and should remain explicit rather than automatic.

**Estimated effort:** small to medium  
**Affected files:** `workspace/common/work_*.fish`

### 4. Consider whether office or research should gain internal fixed workspaces

At present:

- `office` has only wide/tall external task workspaces
- `research` has only wide/tall external task workspaces

This is acceptable under the current design. However, future workflow evolution may justify internal fixed support spaces for these modules, similar to:

- `gtd_chat`
- `gtd_calendar`
- `coding_control`

This should only be done if a stable daily-use support pattern emerges.

**Estimated effort:** medium  
**Affected files:** potential new `internal` workspace files for `office` and `research`

### 5. Continue abstraction cleanup carefully

The current system is already stable and usable. Any future abstraction work should remain conservative.

Candidate abstractions may include shared helpers for:

- application window capture
- on-space final capture
- empty labeled-space destruction
- repeated optional-window logic

This should be approached carefully. The current design already favors explicitness, and future abstraction should only be introduced when it produces clear maintenance benefits.

**Estimated effort:** medium  
**Affected files:** `workspace/common/*` and most module workspace functions

### 6. Watch for residual unlabeled space cases

The major cleanup logic is now good enough for normal usage, and `work_recover_light` can clean empty unlabeled spaces manually. Some display-transition scenarios may still produce transient unlabeled empty spaces.

This no longer blocks normal workspace recovery. If it becomes frequent, improve diagnostics first, then decide whether cleanup should be triggered by a specific workflow command.

**Estimated effort:** small  
**Affected files:** `workspace/common/cleanup_unlabeled_empty_spaces.fish`, `workspace/common/work_diagnostics.fish`

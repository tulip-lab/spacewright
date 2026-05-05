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

These functions apply the display profile and then run:

- `display_reload`
- `work_reload`

They do not automatically force the final workspace mode. The user may then explicitly run:

- `work_wide`
- `work_tall`
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

The system is now considered structurally stable. Future changes should focus on incremental behavioral refinement rather than broad architectural rewrites.

## Current Recommended Usage After Display Switching

When switching to a wide-left external monitor configuration, the current recommended sequence is:

```fish
display_apply_wide_left
work_wide
```

When switching to a tall-left external monitor configuration, the current recommended sequence is:

```fish
display_apply_tall_left
work_tall
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

### 3. Strengthen top-level work orchestration

The current top-level workspace layer already includes:

- `work_reload`
- `work_status`
- `work_mode_status`
- `work_wide`
- `work_tall`
- `work_check`

A future refinement may strengthen this layer by adding:

- stronger summary output in `work_check`
- lightweight checks for stale labeled spaces
- more explicit full-system mode transitions
- optional global recovery helpers

This would improve system-wide maintenance and regression checking.

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

### 6. Finish cleanup of the final unlabeled residual space case

The major cleanup logic is now good enough for normal usage, but one internal unlabeled empty space may still remain in some display-transition scenarios.

This no longer blocks normal workspace recovery, but it is still worth resolving so that the internal display remains fully tidy after repeated monitor changes.

**Estimated effort:** small  
**Affected files:** `workspace/common/cleanup_unlabeled_empty_spaces.fish`

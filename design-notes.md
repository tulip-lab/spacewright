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

## Why Labeled and Unlabeled Space Cleanup Are Separate

The system distinguishes between two different cleanup responsibilities.

`cleanup_unlabeled_empty_spaces` handles empty spaces that do not carry structural meaning. These are usually transient or accidental spaces created during window movement or space creation.

Module-specific cleanup functions such as `gtd_cleanup_wide_spaces` or `research_cleanup_tall_spaces` handle empty spaces that still carry valid labels. These are structured workspaces that have become empty after mode switching or app disappearance.

Keeping these two cleanup mechanisms separate reduces the risk of deleting meaningful workspaces too aggressively while still keeping the space graph tidy.

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

## Maintenance Strategy

The current maintenance strategy is:

1. add reusable mechanics only in `workspace/common`
2. keep module-level workspace behavior explicit and readable
3. prefer small local fixes over broad hidden abstractions
4. use `*_reload` commands as the standard post-edit validation step
5. use `*_mode_status` and `*_status` for regression checking

The system is now considered structurally stable. Future changes should focus on incremental behavioral refinement rather than broad architectural rewrites.


## TODO List

### 1. Further simplify display-resolution logic

Although the internal display UUID has already been decoupled from business-level workspace functions, many functions still retain a transitional pattern based on:

- `get_internal_display_uuid`
- `resolve_target_display`

A future cleanup pass should further simplify display selection by using:

- `resolve_internal_display`
- `resolve_external_display`

directly inside workspace functions where possible.

This change is mainly a maintainability improvement and should reduce repeated display-selection boilerplate across GTD, coding, office, and research modules.

**Estimated effort:** medium  
**Affected files:** most workspace entry functions in `gtd`, `coding`, `office`, and `research`

### 2. Refine ChatGPT ownership handling

The current global rule is intentionally simple:

**the last invoked module owns the `ChatGPT` window**

This rule is acceptable for daily use, but future refinement may improve code clarity by making ChatGPT capture behavior more explicit. Possible directions include:

- defining which workspace functions actively capture ChatGPT
- defining which functions only include ChatGPT opportunistically
- introducing a small shared helper for optional ChatGPT capture

This is not a correctness issue. It is a future maintainability improvement.

**Estimated effort:** small to medium  
**Affected files:** all workspace functions that currently capture `ChatGPT`

### 3. Improve WhatsApp compatibility in `gtd_chat`

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

### 4. Strengthen top-level work orchestration

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

### 5. Consider whether office or research should gain internal fixed workspaces

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

### 6. Continue abstraction cleanup carefully

The current system is already stable and usable. Any future abstraction work should remain conservative.

Candidate abstractions may include shared helpers for:

- application window capture
- on-space final capture
- empty labeled-space destruction
- repeated optional-window logic

This should be approached carefully. The current design already favors explicitness, and future abstraction should only be introduced when it produces clear maintenance benefits.

**Estimated effort:** medium  
**Affected files:** `workspace/common/*` and most module workspace functions
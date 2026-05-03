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

## Common Helper Layer

Shared helpers are located in `workspace/common`.

They are responsible for:

- creating or reusing labeled spaces
- normalizing labeled spaces
- resolving target displays
- focusing displays and spaces safely
- cleaning unlabeled empty spaces
- resolving internal and external display roles

Current core helpers include:

- `find_or_create_labeled_space`
- `prepare_labeled_space`
- `cleanup_unlabeled_empty_spaces`
- `resolve_target_display`
- `resolve_internal_display`
- `resolve_external_display`
- `ws_focus_display`
- `ws_focus_space`
- `set_internal_display_uuid`
- `get_internal_display_uuid`

These helpers allow all module-level workspace functions to share the same lifecycle and display-selection logic.

## Display Configuration

The internal display UUID is no longer hardcoded inside module functions.

Instead, the machine-specific internal display UUID is stored once through:

```bash
set_internal_display_uuid <new-internal-display-uuid>
```

The value is stored as a fish universal variable and reused by all workspace modules.

When moving the workspace system to a new machine, the only required display-specific step is:

```bash
set_internal_display_uuid <new-internal-display-uuid>
```

After that, the normal reload commands can be used.

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

```bash
gtd_reload
coding_reload
office_reload
research_reload
```

These reload commands source both module-local functions and the shared helper functions in `workspace/common`.

## Status Commands

The main inspection commands are:

```bash
gtd_status
coding_status
office_status
research_status
```

Mode-level inspection commands are:

```bash
gtd_mode_status
coding_mode_status
office_mode_status
research_mode_status
```

These commands are intended for day-to-day maintenance and regression checking after changes to workspace behavior.

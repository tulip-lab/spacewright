# Workspace Design Notes

## Overview

This document records the current design notes for the workspace automation system.

The workspace subsystem is responsible for organizing app layouts, mode switching, and task-oriented workspaces across internal and external displays.

## Main Design Split

The system is divided into two main categories.

### Internal fixed workspaces

These are reusable support spaces on the internal display.

Current examples:

- `gtd_chat`
- `gtd_calendar`
- `coding_control`

These spaces are designed to be persistent, reusable, and relatively stable across mode changes.

### External task workspaces

These are task-oriented spaces on the external display.

Current examples include:

- GTD mail, meeting, support, and review workspaces
- coding editor workspaces
- office writing and slides workspaces
- research workspaces

These spaces are created only when their core application is available.

## Core Creation Rule

External workspaces follow a unified rule:

- create the workspace only if the core application exists
- reuse labeled spaces when possible
- avoid creating empty labeled spaces

Examples:

- GTD mail depends on `Thunderbird`
- GTD review depends on `Preview`
- coding editor depends on `Code`
- office writing depends on `Microsoft Word`
- office slides depends on `Microsoft PowerPoint`
- research depends on `Zotero`

## Wide and Tall Modes

The system uses a wide/tall model to switch between layout patterns.

The `*_all` entry points are used to compose a full mode transition.

Examples:

- `gtd_wide_all`
- `gtd_tall_all`
- `coding_wide_all`
- `coding_tall_all`

The design choice is that:

- wide entry points clean opposite tall spaces
- tall entry points clean opposite wide spaces

This keeps behavior predictable and symmetric.

## Cleanup Policy

Cleanup functions only remove spaces that satisfy all of the following:

- belong to the opposite mode
- still carry a recognized label
- are empty

Cleanup is intentionally limited in scope and should not be used as a substitute for correct creation logic.

## GTD Notes

### `gtd_chat`
Persistent internal chat workspace.

### `gtd_calendar`
Persistent internal calendar workspace using:

- `Calendar`
- `Reminders`

### `gtd_review`
Review workspaces are part of GTD.

`gtd_review_wide` uses:

- Finder on the left
- Preview in the middle
- ChatGPT and Notes on the right

`gtd_review_tall` uses:

- Finder and Preview on the upper half
- ChatGPT and Notes on the lower half

## Coding Notes

### `coding_control`
Internal support workspace.

It is valid as long as at least one of these exists:

- `Warp`
- `SmartGit`

Current confirmed layout:

- `Warp` occupies the upper `2/3`
- `SmartGit` uses a fixed absolute position and size

### `coding_editor_wide`
Confirmed layout:

- left `1/3`: ChatGPT
- right `2/3`: VS Code

### `coding_editor_tall`
Confirmed layout:

- upper half: ChatGPT
- lower half: VS Code

## Current Design Goal

The workspace system is intended to be:

- predictable
- composable
- fast to enter from shell or hotkeys
- stable enough for daily work

Further improvements should focus on real workflow gains rather than cosmetic complexity.
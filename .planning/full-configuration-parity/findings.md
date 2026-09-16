# Full Configuration Parity Findings

## Baseline

- The imported SpaceWright runtime already contains the complete pre-extraction
  Fish implementation.
- `v0.1.0-alpha.1` configures only `coding_editor_wide`; all other public
  commands still use direct Fish definitions.
- The current schema supports one generic `primary_helper` runner and simple
  workspace arrays for modes.

## Constraints

- GTD review, meeting, support, AI, chat, and calendar flows contain deliberate
  recovery and fallback-space behavior that must not be flattened into a
  generic JSON interpreter.
- Office workspaces use count-dependent layouts; the algorithm remains Fish
  behavior, while configuration should own identity, apps, target mode, and
  layout profile selection.
- Runner names must be a closed enum mapped inside trusted runtime code. User
  configuration must never execute arbitrary Fish functions.
- Mode order matters because the last invoked module owns shared ChatGPT
  windows.

## Initial Inventory

- Mode-specific families: coding editor, research, GTD support, GTD review,
  GTD mail, GTD meeting, GTD AI, Office writing, and Office slides.
- Aggregate modes: coding, research, GTD, Office, and top-level work for the
  supported solo/wide/tall variants.
- Primary fixed workspaces used by aggregates: coding control, GTD chat, and
  GTD calendar.

## Completed Configuration Surface

- The v1 defaults now describe 28 workspaces, 11 ordered aggregate modes, and
  23 reusable layout profiles.
- Every public solo/wide/tall workspace command has a configured equivalent;
  exhaustive dry-run tests compare the configured path with the retained
  legacy path byte-for-byte.
- Recovery-heavy behavior remains behind seven closed runner adapters. User
  configuration selects only validated runner names and cannot execute an
  arbitrary Fish function.

## Display Placement Finding

- The machine correctly resolves the built-in display as display 1 and the
  external display as display 2; configured wide workspaces target display 2.
- The legacy lifecycle helper created a Space on the currently focused display
  and then transferred it. With stale macOS cross-display Space assignments,
  that transfer could fail to settle and leave workspaces on the built-in
  display.
- Space creation now names the target display directly and retains a verified
  transfer fallback. A failed placement rolls back only the newly created Space
  when it is still empty and unlabeled.
- A controlled live probe created an empty Space directly on display 2,
  verified its display assignment, destroyed it, and verified removal.

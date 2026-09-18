# Changelog

All notable changes follow semantic versioning. This project is pre-release;
configuration and installation contracts may still change before 1.0.

## Unreleased

- Harden the portable v2 contract with unknown-field, unique-label, required
  layout role, duplicate placement, mode usage, and shortcut validation.
- Make the checked-in JSON Schema the structural validation authority and add
  cross-app alias and compiled Space-label conflict diagnostics.
- Compile v2 configuration to a digest-bound runtime so normal workspace
  commands can run without Node.js and never consume a stale plan.
- Add versioned generation metadata plus config status, diff, and explanation
  commands.
- Apply every generic window selector to one fail-closed snapshot and prevent
  one window from satisfying multiple workspace roles; verify final Space
  ownership after mutation.
- Add guarded configuration import, export, backup restoration, read-only app
  discovery, rolling backups, safe object rename/delete, complete selector
  editing, keyboard ordering, unsaved-change protection, and accessibility and
  responsive Configurator checks.

## 0.2.0-alpha.10 — 2026-09-18

- Install the pinned Node and Chromium dependencies in CI before running the
  Playwright configuration round-trip test.

## 0.2.0-alpha.9 — 2026-09-18

- Add a local, token-protected Web Configurator for portable apps, display
  roles, workspace layouts, modes, and structured shortcuts.
- Add v2 configuration validation, v1 migration, deterministic runtime and
  skhd compilation, atomic saves, backups, and machine-local display bindings.
- Add a real-browser configuration round-trip test covering authoritative file
  reads, GUI validation and save, external edits, reload, service restart, and
  restoration without mocking the configuration backend.
- Verify that installed releases contain the complete Web Configurator runtime,
  including its service, compiler, HTML, JavaScript, and CSS assets.

## 0.2.0-alpha.8 — 2026-09-17

- Anchor fixed SmartGit, FlClash/Thaw, and Portfolio Performance bounds to the
  workspace-primary display origin, so an external display at the global left
  origin cannot pull control windows off the built-in display.
- Reconcile `coding_control` before `gtd_chat`, allowing any SmartGit-owned
  Space migration and index changes to settle before restoring the chat label.

## 0.2.0-alpha.7 — 2026-09-17

- Preserve an unmovable Hermes window by moving its owning Space to the target
  display and collecting the remaining GTD AI apps there, avoiding a disruptive
  yabai restart during workspace entry.

## 0.2.0-alpha.6 — 2026-09-17

- Fall back to moving SmartGit's owning Space when macOS accepts but does not
  apply a cross-display window move, keeping `coding_control` on the workspace
  primary display.

## 0.2.0-alpha.5 — 2026-09-17

- Treat Spaces containing only sticky windows as empty during inactive-mode
  label cleanup, while retaining fail-closed live window checks.

## 0.2.0-alpha.4 — 2026-09-17

- Ignore minimized control/chat windows when verifying fixed-space separation,
  matching the runtime's active-window selection rules.

## 0.2.0-alpha.3 — 2026-09-17

- Remove empty labels from inactive solo, wide, and tall workspace families at
  the top-level aggregate boundary.

## 0.2.0-alpha.2 — 2026-09-17

- Bootstrap isolated `work_smoke` child shells from the installed package, so
  `work_doctor` validates an installation without reporting missing commands.
- Exercise the full smoke suite from an installer-produced package in release
  checks.

## 0.2.0-alpha.1 — 2026-09-17

- Configure the complete coding, research, Office, and GTD workspace matrix.
- Add ordered configured modes for every supported solo, wide, and tall flow.
- Preserve recovery-heavy behavior through closed trusted Fish adapters.
- Add exhaustive configured/legacy dry-run parity checks and test isolation.
- Generate read-only observation and verification contracts from configuration.
- Create new Spaces directly on their resolved target display and safely roll
  back an empty, unlabeled Space when placement cannot settle.

## 0.1.0-alpha.1 — 2026-09-17

- Preserve and import the original Mackup workspace history.
- Make the Fish runtime relocatable with separate package, config, and state roots.
- Add v1 JSON configuration, validation, inspection, and read-only plans.
- Run `coding_editor_wide` from configuration with a legacy bypass.
- Add private-release installation, CLI, CI, and optional integration examples.

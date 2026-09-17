# Changelog

All notable changes follow semantic versioning. This project is pre-release;
configuration and installation contracts may still change before 1.0.

## Unreleased

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

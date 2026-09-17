# Full Configuration Parity Progress

## 2026-09-17

- Confirmed both repository worktrees and isolated unrelated Mackup changes.
- Created `feature/full-configuration-parity` from synchronized SpaceWright
  `develop`.
- Established the configuration/Fish boundary: data and ordered composition in
  JSON; recovery, fallback, mutation, and finalization in trusted Fish code.
- Began the exhaustive workspace and mode inventory against the imported
  behavioral baseline.
- Expanded the defaults, schema, configured runtime, public entry routing,
  observation surface, and documentation for the complete workspace matrix.
- Added exhaustive configured-versus-legacy dry-run parity and package test
  isolation.
- Corrected Space placement to create directly on the resolved target display,
  with safe rollback for failed new-Space placement.
- Passed JSON parsing, Fish syntax, diff checks, config validation, idempotent
  install/uninstall tests, and the full workspace smoke suite.
- Confirmed through a read-only live plan that primary workspaces resolve to
  display 1 and wide workspaces resolve to external display 2.
- Confirmed through a controlled live empty-Space probe that direct external
  display creation and cleanup work on this Mac.
- Released `v0.2.0-alpha.2`, including the installed-package smoke bootstrap
  fix discovered during consumer validation.
- Updated the Mackup consumer pin to commit
  `1fc0136851c3d284b7234700892edc48b79aed16` and installed that exact release.
- Passed installed `spacewright config-check`, `work_doctor`, and the explicit
  legacy rollback dry run.
- Applied `work_wide` on the live desktop. Fixed workspaces settled on display
  1, all created wide workspaces settled on display 2, and the resulting window
  distribution was 8 on the built-in display and 12 on the external display.

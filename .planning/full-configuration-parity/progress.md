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
- Released `v0.2.0-alpha.3` with complete top-level cross-mode cleanup, then
  exercised the tall aggregate against the live external display.
- Released `v0.2.0-alpha.4` after live validation showed minimized windows must
  be excluded from fixed-workspace separation checks.
- Released `v0.2.0-alpha.5` after live solo validation showed sticky windows
  must not keep obsolete labeled spaces alive during cleanup.
- Confirmed the final solo aggregate leaves only solo labels on the built-in
  display, with fixed-space separation passing and no inactive wide/tall labels.
- Updated the Mackup consumer pin to commit
  `14f08e113a1cf1a5bc2207c7ccf98329f2dd29ae` and installed that exact release.
- Found that `displayplacer enabled:false` can make an external display
  impossible to re-enable programmatically once macOS stops enumerating it.
  The Mackup consumer now defaults solo display handling to the reversible
  `keep` policy; explicit `disable` remains opt-in with a recovery warning.
- Reconnected and re-enumerated the Mi Monitor, then confirmed the external
  wide display at the left origin and the built-in workspace-primary display
  on the right. BetterDisplay's machine-local protected main-display setting
  now agrees with that arrangement, so the left Dock resolves to the external
  edge.
- Released `v0.2.0-alpha.6` with a SmartGit Space fallback for cross-display
  window moves that macOS acknowledges without applying.
- Released `v0.2.0-alpha.7` with a Hermes-owned Space fallback, keeping Hermes
  together with GTD AI helpers without restarting yabai when its AX window is
  temporarily non-movable.
- Installed alpha.7 and confirmed clean and stale-inherited Fish environments
  both resolve the pinned release through the Mackup startup adapter.
- Released `v0.2.0-alpha.8` after live verification showed fixed control
  bounds must be relative to the built-in display origin when the Mi Monitor
  occupies the global left origin. The release also reconciles coding control
  before GTD chat so a SmartGit-owned Space move cannot erase the final chat
  label.
- Installed alpha.8 and completed the post-restart live wide aggregate with a
  zero exit status. Display health, fixed-space separation, every configured
  module, and final cleanup passed. A final direct `gtd_ai_wide` run confirmed
  Hermes, ChatGPT, Obsidian, and Notes together on the external GTD AI Space.

# Progress

## Completed

- Confirmed clean `develop` at `eabb28a`.
- Created `feature/hardware-display-configurations`.
- Established writable boundary and architectural decisions.
- Added the v3 schema, validator, v2 migration, starter configuration, setup projection, and active-runtime compiler.
- Added hardware-family and display-topology detection with explicit Sidecar classification and fail-closed ambiguity handling.
- Added `setup detect/status/confirm/activate`, v3 CLI validation/compilation, and automatic v3 workspace-mode resolution.
- Added authenticated v3 Configurator APIs for preview, validation, confirmation, activation, and verified save.
- Added the Hardware & Setups editor, including physical-display classification,
  setup duplication, per-workspace configuration selection, and exact layout editing.
- Added MacBook and Mac mini Sidecar combinations, including Mac mini single tall,
  wide+tall, wide+Sidecar, and tall+Sidecar.
- Integrated automatic v3 resolution into state planning, Web preview/execution,
  Fish runtime loading, diagnostics, shortcuts, topology monitoring, and doctor.
- Added v2-to-v3 migration, the v3 schema/example, installation coverage, and user documentation.
- Confirmed a real `Mac16,10` Mac mini with one tall external display as
  `mac_mini/single_tall` in isolated machine state.
- Applied the `coding/tall` workspace through the public `spacewright workspace`
  entry and verified convergence with zero blockers, changes, or warnings.
- Fixed background transitions so they source and invoke the current package
  explicitly instead of accidentally resolving an older installed SpaceWright
  from `PATH`.
- Migrated the maintainer's 12-workspace v2 configuration to v3 in both the
  live config root and the Mackup-managed consumer copy while retaining v2 as
  rollback.
- Added migration completion so every workspace is placed exactly once in every
  generated hardware setup, including the previously omitted `gtd_calendar`.
- Added a dedicated `mac_mini_single_tall` configuration for every workspace;
  these inherit tall layouts but target the Mac mini's sole `primary` display.
- Reconciled shared-window ownership so downstream workspace owners are reapplied
  deterministically when an earlier workspace touches the same app.
- Merged Calendar and Reminders into Chat for Mac mini `single_tall`, removed the
  obsolete empty Calendar Space, and verified the resulting eight active Spaces.
- Added confirmed hardware/setup context to the native transition banner, such as
  `Mac mini: Tall` and `Mac mini: Tall + Sidecar`.

## Validation

- `node --test configurator/test/config-v3.test.mjs configurator/test/setup-cli.test.mjs` — 9 passed.
- `fish -n bin/spacewright` — passed.
- `node --test --test-concurrency=1 configurator/test/*.test.mjs` — 69 passed.
- `fish tests/config-v3.fish`, `config-v2.fish`, and `config.fish` — passed.
- `fish tests/install.fish` and `fish tests/release.fish` — passed.
- `node --test configurator/test/mode-transition.test.mjs` — 11 passed.
- `npm test` — 71 passed.
- Isolated v3 `config-check`, `config-status`, `setup status`, and `doctor` — passed.
- Full live Mac mini `single_tall` verification — completed; follow-up dry run
  reported 0 blockers and 0 changes.
- Real system-Chrome Configurator regression — passed at desktop and narrow viewports.
- `git diff --check` — passed.

## Remaining hardware coverage

- No implementation blocker remains.
- Wide, wide+tall, external+Sidecar, and MacBook setups remain fixture-tested only;
  they require the corresponding physical displays before live acceptance can run.
- Mac mini `single_tall` has passed a complete live acceptance run. Sidecar and
  multi-monitor combinations remain fixture-tested until that hardware is attached.

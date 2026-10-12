# Hardware-aware display configurations

## Outcome

Deliver a complete v3 configuration path that selects a shared hardware profile,
matches a confirmed display setup, resolves per-workspace configurations, exposes
read-only/dry-run CLI and Web Configurator controls, and preserves v2 compatibility.

## Boundaries

- Keep provider implementation inside the SpaceWright repository.
- Update only the explicitly scoped Mackup consumer configuration and pin after
  the provider commit exists; preserve all unrelated consumer work.
- Keep physical display UUIDs and confirmed selections in machine-local state.
- No live display, Space, or window mutation during implementation validation.

## Phases

1. Specify v3 vocabulary, resolution rules, machine state, and v2 migration.
2. Add schema, validation, migration, fixtures, and a read-only resolver.
3. Compile v3 to the existing deterministic runtime and expose CLI detection/status/confirmation/dry-run.
4. Add Configurator onboarding and hardware/setup/workspace-configuration editing.
5. Integrate execution while retaining v2 and compatibility command paths.
6. Run focused tests, Fish syntax checks, complete suite, build/check script, and `git diff --check`.

## Decisions

- Hardware profiles describe families (`macbook`, `mac_mini`, `other`), not individual physical Macs.
- Display setup ids are user-defined; common templates include single wide/tall, wide+tall, and external+Sidecar.
- Workspace configurations are named and referenced explicitly by each display setup.
- Normal workspace commands resolve the active configuration automatically; no routine configuration flag is required.
- Unknown, ambiguous, or unavailable hardware/display observations fail closed before mutation.

## Status

All six phases complete. The v3 contract, migration, hardware/setup resolver,
automatic execution path, Configurator UI/API, documentation, packaging checks,
fixture coverage, and real-browser regression are implemented and passing. Live
acceptance has also passed for a Mac mini `single_tall` setup and the `coding/tall`
workspace. The complete Mac mini `single_tall` run now converges with Calendar and
Reminders sharing the Chat workspace, and the transition banner exposes the
confirmed hardware and display setup. Other physical display combinations remain
fixture-tested until their hardware is available.

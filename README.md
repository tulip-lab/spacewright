# SpaceWright

Configurable macOS workspace orchestration for yabai.

> Status: private pre-release. The history-preserving runtime import,
> relocatable bootstrap, packaging, and full v1 workspace configuration are
> complete.

The portable v2 user module includes semantic validation, a digest-verified
compiled runtime, live state discovery, desired-state comparison, executable
plans, post-apply verification, bounded reconciliation, guarded
import/export/backup flows, and generated shortcut fragments. Personal
configuration remains outside this repository.

SpaceWright turns named work contexts into repeatable macOS Space and window
layouts. It is intended to preserve stable commands such as `work_wide` or
`coding_tall` while moving app names, layouts, mode composition, and personal
preferences into validated user configuration.

## Initial Platform

- macOS
- Fish shell
- yabai
- jq

skhd and displayplacer are optional integrations rather than required runtime
dependencies.

## Web Configurator

Run `spacewright configure` to edit portable apps, named workspaces, display
lanes, solo/wide/tall split layouts, ordering, and structured skhd shortcuts in
a local browser UI. Saving writes only SpaceWright's own configuration root;
it does not modify a Mackup checkout or the user's complete skhd configuration.

See [Web Configurator](docs/configurator.md).

## Inspect, plan, apply, verify

The state-management path is explicit and uses fresh yabai snapshots:

```fish
spacewright inspect
spacewright plan gtd_chat wide
spacewright apply gtd_chat wide
spacewright verify gtd_chat wide
```

`inspect`, `plan`, `verify`, and `capture` never change the desktop. `apply`
refuses unavailable discovery, invalid configuration, missing display bindings,
ambiguous required windows, and missing required windows before invoking an
existing workspace runner. Each non-noop run is locked, journaled under the
state root, verified afterward, and retried at most once unless reconciliation
is disabled. `spacewright recover RUN_ID` is an explicit best-effort restore of
only the matched windows recorded by that run.

See [State discovery and reconciliation](docs/state-reconciliation.md).

## Design Principles

- Safe by default: invalid configuration and missing required windows fail
  before desktop state is changed.
- Inspectable: configuration, selection, movement, layout, and cleanup plans
  have read-only and dry-run representations.
- Configurable without becoming a shell-programming format: data describes
  apps, workspaces, layouts, and modes; Fish implements behavior and recovery.
- Relocatable: package code, user configuration, and machine state have
  separate roots.
- Reversible migration: existing public commands remain available while each
  configured workspace is proven.

## Repository Boundary

SpaceWright owns the portable engine, schema, tests, installer, and releases.
Consumer repositories own personal configuration and integrations. The first
consumer is a Mackup-managed dotfiles repository, but SpaceWright must not
depend on its directory layout or read its source files directly.

See:

- [Architecture](docs/architecture.md)
- [State discovery and reconciliation](docs/state-reconciliation.md)
- [Configuration](docs/configuration.md)
- [Installation and upgrades](docs/installation.md)
- [Release process](docs/releasing.md)
- [Repository boundary and file inventory](docs/repository-boundary.md)
- [Compatibility contract](docs/compatibility.md)
- [Migration plan](docs/migration.md)
- [Import provenance](docs/import-provenance.md)
- [Security and publication](docs/security-and-publication.md)

## Git Flow

- `main`: releases
- `develop`: integration
- `feature/*`: bounded feature work
- `release/*`: release stabilization
- `hotfix/*`: urgent fixes based on a release

The git-flow CLI is not required; the branch model can be followed with plain
Git.

## Configuration Model

The target configuration boundary is:

```text
package defaults + user configuration -> validated effective config
                                            |
                                            v
                                  deterministic Fish runtime
                                            |
                                            v
                                  yabai query / plan / apply
```

User configuration describes app aliases, window roles, workspace labels,
display roles, layout actions, mode composition, and simple cleanup policy. It
will not contain arbitrary shell or jq programs.

## Checkout Bootstrap

For development and read-only validation, source the checkout bootstrap:

```fish
source /path/to/spacewright/conf.d/spacewright.fish
work_command_check
```

The bootstrap resolves `lib/spacewright` from its own location. User config,
state, and optional integration roots can be overridden with the corresponding
`SPACEWRIGHT_*_ROOT` variables documented in
[Architecture](docs/architecture.md).

For a versioned installation from a trusted private checkout:

```fish
fish scripts/install.fish
spacewright config-check
```

## Migration Progress

1. Complete — import the current runtime with relevant history.
2. Complete — separate package, configuration, and state roots.
3. Complete — add v1 schema, validation, inspection, and read-only planning.
4. Complete — prove `coding_editor_wide` with a configured runner and legacy bypass.
5. Complete — package `v0.1.0-alpha.1` and integrate the Mackup consumer.
6. Complete — package `v0.2.0-alpha.8` with every shipped workspace and ordered
   solo/wide/tall composition, exhaustive dry-run parity, read-only observation,
   and target-display Space creation.

## Safety

Read-only validation must never move windows, create or destroy Spaces, change
display geometry, or restart services. Live workspace and display tests require
explicit user authorization.

## License

MIT. See [LICENSE](LICENSE).

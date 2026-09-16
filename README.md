# SpaceWright

Configurable macOS workspace orchestration for yabai.

> Status: pre-alpha migration. The repository currently contains the product
> contract and roadmap; the existing runtime has not yet been imported.

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
- [Repository boundary and file inventory](docs/repository-boundary.md)
- [Compatibility contract](docs/compatibility.md)
- [Migration plan](docs/migration.md)
- [Security and publication](docs/security-and-publication.md)

## Git Flow

- `main`: releases
- `develop`: integration
- `feature/*`: bounded feature work
- `release/*`: release stabilization
- `hotfix/*`: urgent fixes based on a release

The git-flow CLI is not required; the branch model can be followed with plain
Git.

## Configuration Direction

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

User configuration will describe app aliases, window roles, workspace labels,
display roles, layout actions, mode composition, and simple cleanup policy. It
will not contain arbitrary shell or jq programs.

## Roadmap

1. Import the current runtime with relevant history as a legacy baseline.
2. Remove fixed installation paths and separate package/config/state roots.
3. Add JSON Schema, validation, inspection, and read-only planning.
4. Prove one configured workspace while retaining a legacy bypass.
5. Integrate a pinned SpaceWright build into the Mackup consumer.
6. Add installer, CI, versioning, and optional integrations.

## Safety

Read-only validation must never move windows, create or destroy Spaces, change
display geometry, or restart services. Live workspace and display tests require
explicit user authorization.

## License

MIT. See [LICENSE](LICENSE).

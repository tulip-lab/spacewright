# SpaceWright Repository Guidelines

## Purpose

SpaceWright is a configurable macOS workspace orchestrator built on Fish,
yabai, and jq. It owns portable runtime behavior, configuration contracts,
validation, tests, installers, and releases.

This repository must remain usable independently of any one user's dotfiles.
Personal workspace definitions and machine state belong in consumer
configuration, not in the product runtime.

## Repository Relationship

SpaceWright is the provider repository. A separate Mackup repository is the
initial consumer and owns the maintainer's personal configuration, skhd
bindings, display profiles, and version pin.

- Do not read files from the Mackup repository at runtime.
- Do not hardcode a local Mackup path in tracked SpaceWright files.
- Exchange data only through documented configuration and version contracts.
- For cross-repository work, state the writable repository/file boundary
  before editing and recheck both worktrees before staging or committing.
- Commit changes independently in each repository. Update a consumer pin only
  after the referenced SpaceWright commit or release exists.

## Git Flow

- `main` contains release history.
- `develop` is the integration branch.
- Start bounded work from `develop` on `feature/*` branches.
- Stabilize releases on `release/*` branches and urgent release fixes on
  `hotfix/*` branches.
- Do not commit implementation work directly to `main` or `develop`.
- Keep feature branches focused so they can be reviewed and reverted without
  taking unrelated migration work with them.

The git-flow command-line extension is optional. Plain Git commands may be used
as long as the branch model is preserved.

## Architecture Boundaries

SpaceWright owns:

- bounded yabai and jq command wrappers;
- display-role resolution interfaces;
- Space creation, labeling, focus, ordering, cleanup, and verification;
- window selection, movement, layout application, and confirmation;
- deterministic configuration loading and validation;
- dry-run, diagnostics, fixtures, and regression checks;
- package installation, versioning, and upgrade/rollback behavior.

Consumer configuration owns:

- accepted app aliases for a user's installed applications;
- workspace ids, labels, window roles, and selectors;
- layout geometry and mode composition;
- personal shortcut bindings and display profiles;
- primary-display UUID and other machine-local state.

Complex app recovery may remain in explicit Fish adapters. Configuration must
not contain arbitrary shell commands, jq programs, loops, or conditionals.

## Compatibility And Safety

- Preserve documented public Fish command names during migration.
- Fail closed before mutation when configuration, display queries, or required
  window selection fails.
- Every mutating public entry must have a non-mutating `--dry-run` path.
- Read-only validation must not activate apps, create or destroy Spaces, move
  windows, apply display profiles, or restart services.
- Do not run live layout/display commands unless the user explicitly requests
  a desktop-state change.
- Keep a bounded rollback path while a legacy behavior is being replaced.

## Fish Style

- Use Fish syntax consistently and validate changed files with `fish -n`.
- Prefer `set -l` for local variables and `command -q` for command checks.
- Use structured yabai JSON with jq rather than ad hoc text parsing.
- Keep public wrappers thin and put reusable mechanics behind descriptive
  helpers.
- Avoid abstractions that hide window ownership, recovery, or mutation order.

## Validation

Use validation proportional to the phase and risk:

1. documentation and schema checks;
2. Fish syntax checks;
3. fixture-backed, read-only regression checks;
4. dry-run plan comparisons;
5. explicit user-authorized live tests only after the read-only gates pass.

Always run `git diff --check`. Report exactly what was checked and what remains
unverified.

## Migration Discipline

The initial implementation arrives through a history-preserving import of the
existing workspace subtree. Treat imported code as a behavioral baseline, not
as the final package layout.

- Preserve the baseline until equivalent read-only and dry-run checks exist.
- Separate path relocation from behavior changes.
- Separate declarative configuration extraction from runtime refactoring.
- Migrate one simple workspace family before ownership-sensitive GTD flows.
- Do not delete the consumer's legacy runtime until the packaged build has
  passed a real-use observation period and rollback has been tested.

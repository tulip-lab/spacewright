# Full Configuration Parity Plan

## Outcome

Represent every shipped SpaceWright workspace and solo/wide/tall composition in
the versioned configuration contract while preserving the behavior of the
pre-extraction Fish runtime, public commands, recovery paths, ownership rules,
and finalization semantics.

## Writable Boundary

- SpaceWright: configuration, schema, configured dispatch/runtime adapters,
  entry wrappers, tests, and product documentation.
- Mackup after a SpaceWright release exists: user overrides, immutable version
  pin, consumer documentation, and migration records.
- Existing unrelated Mackup modifications remain outside the task.

## Architecture Decision

Configuration owns workspace identity, labels, display roles, app/window roles,
layout geometry, cleanup relationships, and mode composition. Fish retains
bounded mutation, app-specific recovery, multi-window algorithms, fallback
space handling, and finalization. Configured runners are a closed enum mapped
to trusted Fish adapters; configuration cannot name arbitrary commands.

## Phases

1. Inventory every public workspace and aggregate mode against the imported
   baseline.
2. Expand the v1 schema and defaults to cover all workspaces and modes.
3. Add closed configured-runner adapters and route workspace entry bodies
   through them, preserving the emergency legacy bypass.
4. Add exhaustive validation, parity fixtures, dry-run coverage, and
   observation coverage.
5. Run syntax, schema, smoke, audit, package, install, rollback, and read-only
   live-state checks.
6. Run representative live solo/wide/tall validation only after read-only
   gates pass, then release through git-flow.
7. Update Mackup's version pin, install the release, validate the consumer,
   and record the migration.

## Completion Criteria

- Every workspace in the public command map has a valid configuration entry.
- Every solo/wide/tall aggregate has explicit ordered configuration.
- Public command names and dry-run behavior remain compatible.
- Specialized recovery-heavy paths retain their existing Fish behavior while
  consuming declarative facts from configuration.
- Package and consumer rollback paths pass.
- The released package reproduces the pre-extraction workspace effects on this
  Mac for representative solo, wide, and tall runs.

## Status

Implementation and release are complete through `v0.2.0-alpha.7`. The Mackup
consumer is pinned to the immutable release and validated in installed and
rollback modes. Live wide, tall, and solo workspace runs exposed and verified
the cleanup, display-role, SmartGit, and Hermes fallback fixes. The Mi Monitor
is re-enumerated and the external-left role is healthy. One final full live
aggregate replay remains after the next login/restart because an earlier yabai
recovery attempt invalidated existing application AX references for the rest
of the current login.

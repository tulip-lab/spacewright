# Architecture

## Goal

SpaceWright provides a portable engine for turning validated workspace
configuration into predictable macOS Space and window state. It preserves
explicit workflow behavior while separating personal facts from mutation
mechanics.

## Runtime Layers

```text
public Fish commands
        |
        v
configuration loader and validator
        |
        v
snapshot -> plan -> preflight -> apply -> verify
        |                            |
        v                            v
display/space/window model      bounded recovery adapters
        |
        v
yabai + jq (+ optional System Events fallbacks)
```

### Public command layer

Stable Fish commands remain the user-facing API. During migration, thin
wrappers may dispatch either to the legacy implementation or the configured
runner. Command names do not encode package installation paths.

### Configuration layer

The configuration layer loads package defaults and user configuration, checks
the schema version, rejects unsupported or ambiguous definitions, and produces
one deterministic effective configuration.

It owns declarative facts:

- app keys and accepted names;
- workspace ids and labels;
- display roles;
- required and optional window roles;
- explainable window selectors;
- grid or bounded geometry actions;
- mode composition and simple cleanup policy.

It does not own execution logic, shell fragments, arbitrary jq, retries, or
app-specific recovery programs.

Version 3 resolves `hardware profile -> display setup -> workspace
configuration` before entering the existing deterministic runtime. Portable
files describe Mac families and semantic display kinds; `machine.json` alone
stores physical UUID bindings, Sidecar classification, and confirmation of a
topology. An unmatched, ambiguous, or unconfirmed topology fails before the
snapshot plan can mutate anything.

### Snapshot and plan layer

One read-only snapshot captures displays, Spaces, and windows for a planning
operation. Planning resolves configuration against that snapshot and explains:

- the target display and Space;
- selected and missing windows;
- ownership conflicts;
- planned movement and layouts;
- cleanup and finalization actions.

Planning must be idempotent and non-mutating.

### Apply and verify layer

Application begins only after configuration and required-window preflight
passes. Mutations use bounded yabai wrappers, confirm final ownership, apply
layout, finalize ordering/cleanup, and verify the resulting contract.

### Recovery adapters

Some applications expose non-standard or transient windows. Explicit Fish
adapters may implement bounded recovery for these cases. Recovery remains code
because making JSON a programming language would make plans unsafe and hard to
review.

## Roots And State

The final runtime will distinguish:

- **package root**: versioned SpaceWright code, schema, and defaults;
- **configuration root**: user-authored portable configuration;
- **state root**: machine-local UUIDs, caches, and runtime observations.

The runtime now exposes explicit root variables:

- `SPACEWRIGHT_ROOT`: package runtime (`lib/spacewright`);
- `SPACEWRIGHT_CONFIG_ROOT`: user configuration (XDG config fallback);
- `SPACEWRIGHT_STATE_ROOT`: machine-local state (XDG state fallback);
- `SPACEWRIGHT_DISPLAY_PROFILES_ROOT`: optional display integration;
- `SPACEWRIGHT_SKHD_ROOT` and `SPACEWRIGHT_YABAI_ROOT`: diagnostic-only
  integration locations.

The Fish bootstrap resolves the package root from its own real path, so a
checkout or installed symlink can move without rewriting runtime source files.
Consumer configuration may override any integration root explicitly.

## Integration Boundary

skhd triggers commands but does not define runtime behavior. displayplacer
profiles arrange monitors but do not express workspace intent. yabai provides
the low-level Space/window API but does not own SpaceWright configuration.

SpaceWright may ship examples and adapters for these tools. It must not replace
or overwrite a user's live configuration silently.

## Consumer/Provider Model

SpaceWright is a versioned provider. The Mackup repository is the initial
consumer:

```text
SpaceWright release or immutable commit
                  |
                  v
          Mackup version pin
                  |
                  +--> user configuration
                  +--> skhd integration
                  +--> display profiles
```

Cross-repository integration is one-directional at runtime. SpaceWright never
imports Mackup source files. Mackup exposes configuration at the documented
configuration root and selects the SpaceWright version it consumes.

## Failure Model

The runtime fails closed before mutation on:

- missing or unsupported configuration versions;
- schema or jq failure;
- display query/resolution failure;
- missing required windows;
- ambiguous label or ownership state that cannot be safely retargeted.

After mutation begins, operations are bounded, observable, and verified. A
failure returns non-zero and preserves enough diagnostic context for explicit
recovery; it must not trigger an unbounded retry loop.

## Evolution Strategy

The imported runtime is a behavioral baseline. Evolution is intentionally
staged:

1. preserve history and behavior;
2. make paths relocatable without changing semantics;
3. introduce read-only configuration and comparison;
4. migrate a simple workspace behind a bypass;
5. expand only after fixture and daily-use evidence.

This keeps deterministic runtime mechanics separate from personal workflow
design and makes each architectural change independently reversible.

## Execution contract (compiler 5)

The policy engine selects objects once. `window-policy.mjs` owns selector,
cardinality and ambiguity semantics; `layout-policy.mjs` computes per-window
Office, Dia and declarative geometry; `plan-backend.mjs` composes the closed
backend commands. The Fish backend consumes the immutable execution envelope
and never substitutes another window. Every selected window carries its ID,
application, PID, available process lifetime identity and bundle identifier.
Every existing target Space carries its UUID, resolved again before use.

The shared `execution-coordinator.mjs` owns leases and process groups for CLI,
Web tasks, interactive requests and direct public mutations. A lease requires
both a random token and verified process ancestry; an environment variable is
not sufficient. Unknown live owners are preserved. Nested children register
under the same lease. Cancellation escalates TERM to KILL after 750 ms and
ownership is retained if a registered group remains alive.

State has three lifetimes:

| Lifetime | Location | Contract |
| --- | --- | --- |
| Machine state | `machine.json` | Confirmed hardware, display bindings and setup choices |
| Execution state | `runs/`, `execution-context/`, `execution.lock/`, transition history | Immutable input, selected objects, commands, effects and terminal results |
| Short cache | `cache/bad-windows/` | 60-second default TTL; app/PID/bundle and runtime generation must still match |

`config-store.mjs` owns atomic output, generation metadata and the configuration
write guard. Generation format 2 binds the source bytes, compiler version,
resolved runtime, hardware identity, display topology and machine state. v3
Fish loading resolves live topology before exposing runtime; a source-only
cache hit cannot authorize execution. A save guard remains after an incomplete
write, so readers fail closed rather than combine generations. An explicit
`spacewright config-compile --repair-incomplete-save` may rebuild a generation
only after its prior writer has stopped. It does not discard a live writer.

The server delegates discovery, configuration generation/storage, task
lifecycle and automation policy to focused modules. Its HTTP authorization,
route handling and event monitor remain in `server.mjs`.

### Recovery adapters

Legacy Office/GTD app reopen, activation and native-fullscreen adapters remain
explicit Fish code. Their inputs are configured app/role/layout and the shared
execution deadline; output is a status plus diagnostics; side effects include
activation, app restart or fullscreen changes. Issued window commands propagate
failure. A pinned plan does not invoke an adapter to replace a missing or
fullscreen window: recovery must finish, rediscover and produce a new plan.
This conservative boundary intentionally blocks a required window needing app
recovery rather than changing its identity silently. Declarative existing-window
placement, Office multi-document geometry and Dia multi-window geometry use the
pinned backend. Automatic app recovery inside a pinned execution is not yet
supported; legacy adapter recovery still needs a separate explicit invocation.

## Remaining hardening boundaries

The existing-window pinned path and shared lease are implemented and covered by
isolated tests. This is not a complete migration of every legacy adapter:

- Aggregate Sandbox collection and anchored postprocessors still calculate
  some actions inside Fish. `ws_window` refuses a window absent from the
  immutable envelope, so these flows can fail closed until their complete
  object lists and geometry are added to the planner. Space creation, ordering
  and cleanup effects remain explicitly nonrecoverable.
- Single-workspace pinned execution preserves opposite variants. Add a planner
  action for the exact workspace's opposite-variant Space UUIDs, together with
  fresh completeness and occupancy gates, before enabling local destruction.
- Fixed adapters (coding control, GTD chat/calendar) retain their explicit
  recovery bodies on the legacy path. Their custom geometry, reopen effects
  and verification need dedicated planner contracts; the pinned path only uses
  declared existing-window layouts and cannot promise full adapter equivalence.
- Cancellation and total deadlines cover the shared child process machinery.
  Individual legacy recovery adapters still have their own bounded confirmation
  loops; consolidate those into a lease-wide retry budget before removing the
  legacy path. Recovery attempts currently record issued operations, not a
  durable per-command acknowledgment that survives an abrupt controller kill.
- The HTTP event monitor remains in the server, although discovery, storage,
  task coordination and pure automation policy have separate modules. Splitting
  monitor lifecycle and all remaining persistence routes requires further work.

True macOS app recovery, native fullscreen transitions, yabai label/Space
reordering races and real display-profile application require an explicitly
approved desktop test. Fixture convergence is not evidence of those behaviours.

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
cache hit cannot authorize execution. Generation construction also verifies that
source bytes describe the exact configuration being compiled. A save guard remains after an incomplete
write, so readers fail closed rather than combine generations. An explicit
`spacewright config-compile --repair-incomplete-save` may rebuild a generation
only after its prior writer has stopped. It does not discard a live writer.

The server delegates discovery, configuration generation/storage, task lifecycle
and automation policy to focused modules. `automation-monitor.mjs` owns serialized
sampling, topology debounce, event dispatch and stop/drain. HTTP writes use an
async-local save scope; unrelated HTTP readers cannot bypass a running writer.
Responses are sent after the save guard is released. Binding updates, setup
activation, backup/history restoration and topology activation use that guard.

### Fixed planning and preparation

`finalization-policy.mjs` adds exact opposite-variant cleanup candidates and a
synthetic mode Sandbox workspace. The Sandbox uses independently pinned IDs and
explicit balanced float grids; its geometry uses the same comparison as ordinary
workspaces. Anchored postprocessors have fixed object lists. Hermes expansion is
computed from final role ownership and configured labels. Primary separation uses
those same workspace assignments rather than rerunning legacy selectors.

`pinned-executor.mjs` consumes only the immutable workspace/actions. Runtime command IDs shared by modes do not replace the requested variant
contract; role compilation uses that variant directly. Every step
rediscovers and resolves physical displays and Space UUIDs, checks object identity
and selectors, and validates the command's postcondition. Creation records the
new UUID before labeling or subsequent placement. Cleanup rechecks complete,
fresh occupancy, label/display identity and a surviving Space; ordering carries
its workspace/UUID/display list and resolves both source and anchor again.
New mode objects invalidate the census; they are never silently collected.
Single-workspace cleanup includes only that workspace's configured opposite
labels. Occupied, conflicting or last-survivor candidates are retained/rejected.

`adapter-preparation.mjs` defines observed-app refresh and native-fullscreen
preparation inputs, side effects, eight-second phase bounds and verification.
The explicit Fish preparation entry dispatches these closed actions. Office,
Dia, Outlook/Preview and fixed adapters retain their legacy Fish recovery bodies.
Outlook preparation uses activate/reopen; other refreshes use the configured app
name. Minimized windows are excluded. Preparation consumes the shared recovery
budget, records input/output incarnations, then requires rediscovery and a new
immutable plan with a persisted relation to its predecessor. A missing object
inside an established layout plan never selects a replacement.

Grid and canvas absolute geometry are compared and applied by the same policy.
`grid-geometry.mjs` models yabai's constrained display bounds, padding and edge
gaps, using the read-only `spacewright-screen-geometry` native helper. All grid
postconditions use a two-pixel tolerance rather than a percentage of the full
screen. Native geometry/configuration discovery failure blocks mutation; a
changed usable frame, padding or gap invalidates an issued display contract.
Tall splits remain configured by `settings.tallTopPercent`, including 49/51.
Coding-control absolute positions are offsets from its target display origin.
Fixed adapters with no selectable windows stay inactive. A foreign occupant
blocks workspace-scoped execution; a mode may move it only through an explicit
other workspace/Sandbox assignment. Persistently non-movable foreign occupants
block the mode instead of being reported as separated. Existing selected optional
windows propagate failures like required ones.

### Shared budgets and durable operations

The lease initializes `settings.executionBudgets`: confirmation 256, commandRetry
2, appRecovery 2, serviceRecovery 1 and reconciliation 1 by default. Schema limits
bound overrides. Every consumer verifies token, owner lifetime and ancestry;
updates use an exclusive writer gate and durable atomic budget document. Nested
processes share the owner deadline and counters. Cancellation prevents later
budget consumption; pinned apply disables automatic service restart. Legacy
confirmation/retry loops charge the same run when a lease is present.

`process-worker.mjs` waits for an inherited pipe grant. The coordinator persists
its process-group identity before granting execution. A crash before registration
therefore cannot launch an untracked mutator. TERM escalates to KILL with a bounded
wait; an unrecognized or still-active process group retains ownership.

`operation-journal.mjs` synchronizes intent, command exit acknowledgment and queried
postconditions to individual files in `runs/<run-id>.operations/`. Records
separate attempted/unknown, verified success, failure, cancellation and timeout.
Selected-but-unoperated objects never become recovery candidates. Interrupted
controllers import durable operations into failed journals after stopping their
registered groups. Storage failures block further mutation and report the last
available state on stderr. Recovery resolves each original UUID anew and verifies
each command plus final Space/frame/identity; replacement incarnations use their
actual pre-layout snapshot, rather than an old object with a reused ID.

## Remaining hardening boundaries

The migrated paths are fixture-verified, not a claim of full legacy equivalence.
App-owned Space fallback and AppleScript/System Events bounds for persistently
non-movable SmartGit, DingTalk, Calendar, Outlook or Preview windows remain in
legacy adapters. They can select scriptable windows by app-wide heuristics, so
forwarding them through an immutable window envelope would break its identity
contract. The fixed path fails closed when explicit refresh cannot make its
planned role selectable. The next migration must establish an independently
verifiable mapping from the yabai identity to the scriptable/AX window, then plan
any whole-Space transfer and foreign-window handling explicitly.

Standalone legacy compatibility helpers remain available; they do not provide
all of the immutable aggregate apply guarantees. Legacy app-wide scripting bounds charge the shared retry allowance for fallback
methods and check execution admission between commands. Their target selection
still needs that same fixed identity migration. Deleted/created Spaces, app activation/reopen/fullscreen
changes and display-profile effects are reported as nonrecoverable. There is no
promise of complete desktop rollback.

Missing yabai AX references are a distinct observation phase: visit each
affected Space by UUID, restore focus, and replan only after the same native
window/process objects acquire AX references. Optional app roles do not bypass
this phase. Persistent failures stop the run without automatic service restart.
Observation can precede one bounded app-recovery phase; layout waits for the
resulting fixed plan. Recovery uses its verified pre-layout snapshot.
Only tiny, unselected, non-resizable AXDialog helpers (verified native bounds
up to 100×40 points) may be recreated without invalidating the layout census;
ordinary dialogs and full discovered occupancy still guard execution and
Space destruction. Indexed collection fallback verifies a stable last-object
endpoint and every intervening UUID rather than treating query failure as
end-of-list. Both v2 and v3 enforce the schema's numeric execution limits.

Real macOS app recovery, usable-screen grid geometry, native fullscreen, yabai
Space reordering and display profiles require explicitly authorized desktop
observation. An authorized Mac mini single-tall run on 2026-10-15 converged with
zero remaining layout changes, including the configured 49/51 split, after one
manual yabai restart repaired its AX registry. Other hardware setups and
persistent AX recovery remain outside that live validation.

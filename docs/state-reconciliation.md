# State discovery and reconciliation

SpaceWright treats a workspace change as a state transition instead of a blind
script invocation:

```text
Discover -> Compare -> Plan -> Apply -> Verify
                                      |
                                      +-> one bounded retry when enabled
```

## Read-only discovery

`spacewright inspect [--json]` queries displays, Spaces, and windows once and
normalizes the result into a versioned snapshot. Physical display UUIDs are
resolved to portable roles through the machine-state file. Query failure
produces an unavailable snapshot; it is never interpreted as a solo topology.

Window titles are available to the matching engine but the normal human
overview prints application names only. JSON output is intended for local
diagnosis and may include titles returned by yabai.

## Desired state and comparison

`spacewright plan TARGET [MODE]` supports one workspace, an aggregate mode, or
`--profile=ID`. It compiles the current v2 configuration, then compares exact
Space labels, display bindings, window selectors, Space membership, and
approximate normalized geometry with the fresh snapshot.

Drift is classified as:

- `blocker`: execution must fail closed, such as an unavailable snapshot,
  disconnected display binding, duplicate Space label, missing required
  window, or ambiguous required match;
- `change`: Space creation/movement, window movement, geometry, or ordering is
  required;
- `warning`: an optional window is missing or ambiguous.

Selectors support application aliases, optional bundle identifiers, movable,
visible and non-empty-title constraints, title include/exclude rules, and AX
role/subrole. Standard yabai snapshots do not expose bundle IDs, so portable
application-name matching remains the fallback unless a richer discovery
source supplies a bundle ID.

For aggregate modes, workspace order also defines final ownership of shared
applications by default: the last active workspace that declares an app owns
its window. A role may instead set `ownership: "independent"` when selectors
assign distinct windows from one application to different workspaces.
Earlier declarations remain visible in diagnostics as superseded matches, but
do not produce contradictory movement or missing-window drift. Office document
workspaces migrated from the Office adapters declare
`activation: { "type": "windowPresent", "role": "primary" }`; an inactive
workspace does not require an empty Space. Other variants default to always
active. Window roles default to `cardinality: "one"`; adaptive roles such as
GTD Support's Dia role use `"many"`, select every eligible window, and verify
Space membership without inventing a singular geometry comparison.

`contextualApps` is the closed exception for a single shared assistant window.
The reconciler maps the pre-transition focused Space label back to a workspace
id, uses that workspace when it is eligible, and otherwise uses the configured
fallback. When `focusOwner` is true, the selected owner becomes the mode's
final focus, which also makes later verification resolve the same ownership.

Space ordering is compared explicitly per display lane. A converged aggregate
plan is a true no-op; ordering is applied only when the discovered order is
wrong or Space creation/movement requires a final reorder.

When yabai has restarted and labels are gone, comparison can recover a Space
identity from its uniquely matching owned windows and expected display. The
plan reports `recover_space_label` instead of creating a duplicate Space. If
the evidence points to zero or several candidate Spaces, discovery remains
conservative and leaves normal creation/recovery to the bounded runner.

## Execution, journals, and recovery

`spacewright apply --dry-run` follows the same discovery and planning path but
performs no mutation. Without that flag, `spacewright apply` acquires the
execution lock, computes an immutable plan, and performs a second preflight
discovery. If the snapshot, configuration digest, or plan changed, the run is
journaled as `stale` and no mutation is attempted. The lock serializes CLI,
Web, and automation mutations. Lock recovery is conservative: a newly created
ownerless lock receives a grace period, live owners are checked against the
SpaceWright state CLI, and stale locks are quarantined atomically before they
are removed.

Only workspaces with change drift are invoked. Any mutating workspace batch or
detected empty-Space/order drift ends with one closed mode finalization step;
that step collects unmanaged windows, removes safe empty Spaces, verifies
ordering, and restores focus. Closed postprocessors retain their configured
anchors. The existing Fish runners remain the mutation backend. Output, the plan,
before/after snapshots, exact per-command lifecycle, and verification are
written to:

```text
$SPACEWRIGHT_STATE_ROOT/runs/<run-id>.json
```

After execution, SpaceWright discovers state again. If executable drift remains
and reconciliation is enabled, it performs one retry and verifies once more.
It never loops indefinitely.

An empty Sandbox, or an unlabeled Space containing only a headless surface, is
reported as `empty_space_cleanup_required` instead of being hidden behind the
Fish backend. A generic headless surface must have no title or AX role, be
invisible and non-movable/non-resizable, and have no AX reference. This keeps
the cleanup rule narrow while covering background root surfaces left by apps
such as media players.

`spacewright recover RUN_ID --dry-run` lists the still-present candidate
windows without changing them. Recovery without that flag is explicit and
best-effort. It restores the
original Space and absolute frame only for windows matched by that run. It does
not undo application launches, recreate deleted Spaces, reverse displayplacer
changes, or restore windows that no longer exist. Recovery itself receives a
journal.

## Workspace capture

`spacewright capture [ID] [MODE]` converts the focused or selected Space into an
unsaved canvas-layout draft. The Web configurator exposes the same operation as
**Capture into editor**, reuses existing app definitions by alias, and assigns
the workspace to a display lane when that display has a known role. Saving is a
separate, validated action.

## Profiles and topology events

Profiles may declare only closed orchestration fields:

```json
{
  "name": "Research",
  "mode": "wide",
  "workspaces": ["research", "reading"],
  "displayConfig": { "profile": "wide_left" },
  "focusBehaviour": { "workspace": "research" },
  "settings": { "reconcile": true }
}
```

A requested display profile is an explicit orchestration action, even when the
workspace comparison is otherwise converged. The requested workspace is
focused after display and workspace actions so later mutation cannot steal the
final focus. A focus-only mismatch is represented as ordinary change drift and
therefore remains visible in plans and verification.

Topological automation uses stable sampling and a cooldown. The optional root
settings are `eventAutomationEnabled`, `topologyStableSamples` (1–12), and
`topologyCooldownSeconds` (0–600). Automation is serialized through the same
task queue and execution lock as manual runs.

A wake hook can deliver a closed event to a running configurator:

```fish
spacewright event wake --dry-run
spacewright event wake
```

Only enabled matching rules run, and only when event automation is enabled.

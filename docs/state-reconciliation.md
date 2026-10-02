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
applications: the last active workspace that declares an app owns its window.
Earlier declarations remain visible in diagnostics as superseded matches, but
do not produce contradictory movement or missing-window drift. Office document
workspaces are inactive when their primary Word or PowerPoint window is absent;
an inactive workspace does not require an empty Space. Adaptive runners that
lay out several matching windows under one role report ambiguity as a warning
without comparing one arbitrary window to a singular geometry rule.

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
performs no mutation. Without that flag, `spacewright apply` recomputes the plan immediately before mutation. A single
execution lock prevents concurrent Web, automation, and CLI runs. The existing
Fish workspace runners remain the mutation backend, preserving their startup
and recovery adapters. Output, the initial plan, before/after snapshots, and
verification are written to:

```text
$SPACEWRIGHT_STATE_ROOT/runs/<run-id>.json
```

After execution, SpaceWright discovers state again. If executable drift remains
and reconciliation is enabled, it performs one retry and verifies once more.
It never loops indefinitely.

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

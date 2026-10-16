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
produces a `partial` or `unavailable` snapshot with missing query ranges; it is never interpreted as a solo topology.
If a display or Space collection is truncated, indexed fallback first queries
the last object, reads every index through that endpoint, and confirms the
endpoint again. Missing samples, duplicate identities, invalid indices and a
changed endpoint leave discovery incomplete.

Window titles are available to the matching engine but the normal human
overview prints application names only. JSON output is intended for local
diagnosis and may include titles returned by yabai.

A window without a yabai AX reference has unknown capabilities, title and AX
role; it is not evidence that its optional app is absent. Apply plans a bounded
visit to each affected Space, restores the original focus, then rediscovers and
replans before layout. Space UUIDs and window/process identities are checked
before and after the visit. If AX references remain unavailable, diagnostics
name the affected apps and window IDs. The preview declares a fallback that
allows one yabai restart before layout, sharing the lease's `serviceRecovery`
budget and total deadline. A zero service-recovery budget disables it. This
fallback requires complete discovery, exclusively float Spaces and no native
fullscreen windows; it refuses ambiguous labels or changed identities.

Before restarting, it durably saves display/Space/window identities, Space
labels, per-Space padding and gaps, external-bar settings and focus under
`service-recovery/RUN_ID.json` in the state root. Restart reloads the user's
`yabairc`, including its rules and signals. Labels and settings are restored by
fresh UUID lookup, never cached Space indexes. A new immutable plan is required
before any window layout. Persistent AX failure stops without a second restart.
Other errors, cancellation and total-deadline expiry never trigger recovery.
A real native window with missing AX information still occupies its Space for cleanup.

`spacewright repair-yabai --dry-run` previews the same guarded recovery without
changing the desktop. `spacewright repair-yabai` explicitly runs it. If restart
or restoration is interrupted, the error reports the saved checkpoint and
`spacewright repair-yabai --resume=RUN_ID` restores it without another restart.
Unfinished restoration blocks subsequent apply runs until it is resolved;
changing Space ownership, window identity or display topology stops restoration.
Recovery is not a guarantee against external application or yabai defects.
Observation may be followed by one app-recovery phase when the newly available
metadata requires it. Each phase records its predecessor and successor plan;
layout starts only after both phases finish. The same lease, total deadline
and execution budgets apply throughout.

## Desired state and comparison

`spacewright plan TARGET [MODE]` supports one workspace, an aggregate mode, or
`--profile=ID`. It compiles the current v2 configuration, then compares exact
Space labels, display bindings, window selectors, Space membership, and
pixel geometry with the fresh snapshot. Grid verification uses the usable macOS
display frame plus yabai padding and edge gaps, with a two-pixel rounding
tolerance. `settings.tallTopPercent` is applied to the same grids in planning,
execution and verification; 50/50 cannot satisfy a configured 49/51 split.
Adjoining Tall rows share transformed boundaries, including a middle row that
crosses the midpoint. This permits a three-row canvas without gaps or overlap
when the split percentage changes. Detached centered overlays keep their
historical geometry. A layout region must still be large enough for its app's
minimum window size. On a folding display, keep the configured physical panel
boundary when adjusting regions; a minimum-size failure must not be solved by
replacing the two panels with three equal rows. Two Sandbox windows on a
portrait display stack vertically, and Tall mode preserves the configured
top/bottom ratio instead of narrowing both windows into side-by-side columns.
Native window frames are read from WindowServer by unique ID and owner PID,
because yabai's AX event cache can retain old coordinates after a display
change even when a geometry command has actually succeeded. Missing or reused
native objects stop verification rather than falling back to cached frames.

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
Space membership and the same per-object adapter geometry used for execution.

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
discovery. If target-relevant preconditions, configuration digest, or plan changed, the run is
journaled as `stale` and no mutation is attempted. The lock serializes CLI,
Web, and automation mutations. Lock recovery is conservative: a newly created
ownerless lock receives a grace period, live owners are checked by process lifetime and lease ancestry, and stale locks are quarantined atomically before they
are removed.

Only workspaces with change drift are invoked. Single-workspace execution never
collects Sandbox, globally orders or finalizes other workspaces. An aggregate-mode workspace batch or
detected empty-Space/order drift ends with one closed mode finalization step;
Sandbox objects and geometry are already pinned in the plan before execution.
The final step only consumes listed cleanup and ordering objects. Explicit focus
orchestration is applied last. Closed postprocessors retain their anchors and
fixed object lists. Public Fish wrappers dispatch the fixed backend. Output, the plan,
before/after snapshots, exact per-command lifecycle, and verification are
written to:

```text
$SPACEWRIGHT_STATE_ROOT/runs/<run-id>.json
```

Tiny unselected, non-resizable `AXDialog` helpers with verified native bounds
(at most 100×40 points) are retained in discovery and fresh Space-occupancy
checks but excluded from the layout object census. Recreating one while moving
its parent does not invalidate the plan. Ordinary dialogs, selected objects and
new layout windows still require unchanged identities or a new plan.

After execution, SpaceWright discovers state again. If executable drift remains
and reconciliation is enabled, it performs one retry and verifies once more.
It never loops indefinitely.

An empty managed Sandbox is reported as `empty_space_cleanup_required` instead
of being hidden behind the Fish backend. With the explicit `all` cleanup
policy, a safe empty unlabeled Space can also be reported. The default
`managed` policy preserves unlabeled user Spaces, `none` disables cleanup, and
a single-workspace target never runs global cleanup. A generic headless surface
must have no title or AX role, be invisible and non-movable/non-resizable, and
have no AX reference. This keeps the cleanup rule narrow while covering
background root surfaces left by apps such as media players.

`spacewright recover RUN_ID --dry-run` lists the still-present candidate
windows without changing them. Recovery without that flag is explicit and
best-effort. It restores the
original Space and absolute frame only for objects with issued window operations
recorded by that run. Each operation checks application, PID, available process
lifetime and bundle identity; original Space UUIDs are resolved to current
indices. Rediscovery verifies both membership and frame after restoration. It does
not undo application launches, recreate deleted Spaces, reverse displayplacer
changes, or restore windows that no longer exist. When preparation occurred, the recovery
baseline uses the verified snapshot immediately before layout, including the
recovered window capabilities. Recovery itself receives a
journal before discovery begins. SIGINT and SIGTERM stop further preflight or
recovery work, terminate the active child process group, and persist a
cancelled journal with an interrupted step when one had started.

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

Apply executes a requested display profile once, before adapter preparation and
layout. It then waits up to five seconds (within the same execution deadline)
for stable display geometry and creates a new layout plan. Both plans and their
relationship are recorded in the run journal. Reconciliation does not repeat
the display command.

This phase permits geometry and display-index changes for the same physical
displays. It preserves the configuration, machine bindings, selected window
identities and ownership, Space identities, and execution scope. Physical
display replacement, changed hardware/setup selection, incomplete discovery,
or an unstable display state stops layout and leaves the attempted display
action in the journal. A failed display action is not automatically rolled back.

Topological automation uses stable sampling and a cooldown. The optional root
settings are `eventAutomationEnabled`, `cleanupEmptySpaces` (`managed`, `all`,
or `none`), `tallTopPercent` (35–65), `topologyStableSamples` (1–12), and
`topologyCooldownSeconds` (0–600). Automation is serialized through the same
task queue and execution lock as manual runs.

A wake hook can deliver a closed event to a running configurator:

```fish
spacewright event wake --dry-run
spacewright event wake
```

Only enabled matching rules run, and only when event automation is enabled.

## Preconditions and terminal outcomes

The full snapshot remains diagnostic. The plan digest includes relevant
configuration, ownership/eligible candidates, selected-window identity and
frame, target Space identity and display geometry. Unrelated title or frame
changes do not invalidate a workspace preview. Optional ambiguous roles are
skipped instead of selecting an arbitrary candidate. Minimized/native fullscreen
windows are excluded from immutable layout selection. Observed fullscreen or
unmovable complex-app candidates may instead produce an explicit preparation
phase. Successful preparation records its new window identities and a new plan;
it cannot alter an existing layout plan's selected objects.

All established journals finish as completed, failed, stale, cancelled or
timed out. A completed apply requires fresh convergence and unchanged selected
identities. Interactive and Web controllers require this verification result,
not merely a zero exit code. One total deadline covers discovery, backend
commands and a single optional reconciliation. Service recovery is disabled
inside pinned window execution; the pre-layout AX recovery and retained adapters
share the service-recovery allowance per lease. Read-only confirmation polling, retries and app/service recovery consume atomic
lease-wide counters in `settings.executionBudgets`; the owner deadline never
resets for a subprocess.

A geometry failure reports the app/window ID and expected versus actual frame
in the CLI, journal and interactive error banner. Applications may enforce a
minimum window size larger than a configured region. Such a layout must be
adjusted; service restart or relaxed verification cannot make it converge.

Recovery results distinguish completed, partial, skipped, failed and cancelled.
Space creation/destruction, display profile changes and other non-window effects
are reported as nonrecoverable. Individual operation files persist intent before issue, exit acknowledgment
before verification, and fresh postconditions before verified success. A crash
between these points preserves an attempted/unknown result. Recovery uses only
operated objects, including the actual pre-layout incarnation after preparation;
it never restores merely selected windows. App and Space side effects remain
nonrecoverable, and there is no complete desktop rollback guarantee. If the state
directory becomes unwritable, the controller reports terminal status on stderr;
it cannot guarantee an on-disk terminal journal while storage is unavailable.

## Exact local cleanup

Workspace `apply`, Web execution and interactive `workspace` all use the same
configured opposite-variant labels and discovered UUIDs. Inactive workspaces also
plan their empty target UUID; labels shared by their opposite modes are deduplicated. Shared runtime command
IDs do not widen the scope. Duplicate labels or cross-workspace label claims
block execution. Occupied and last-survivor Spaces are retained with a reason;
cleanup never treats an unselected window as absent. Each deletion rechecks full
fresh discovery and resolves its UUID after any previous renumbering. This local
phase has no global Sandbox, ordering or finalization step.

## Validation boundary

The inherited macOS process sandbox and temporary HOME/config/state/cache/log
roots in `scripts/isolated-check.mjs` block real desktop programs, including
absolute executable paths. Explicit fake commands provide fixture behavior.
A child lacking a parent's Fish mock is tested to remain blocked. Smoke is a
batch of independent fake scenarios and receives explicit test-batch allowances;
normal run-budget limits are verified in separate concurrent lease tests. The full
check entry enters that sandbox before installation, packaging or smoke checks.
Persistently non-movable app-owned Space/AX fallback remains a migration boundary
as documented in `architecture.md`; fixture success does not establish it.

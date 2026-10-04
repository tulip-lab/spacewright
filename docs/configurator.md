# Web Configurator

## Start

```fish
spacewright configure
```

The command starts a local HTTP service on a random loopback port and opens the
editor in the default browser. It never binds to a LAN interface. A random
session token protects every write request, and the service sends a restrictive
Content Security Policy.

The configurator requires Node.js 20 or newer. Existing v1 configurations and
ordinary Fish commands continue to work without opening the configurator.

## Files and ownership

The editor owns only:

```text
$SPACEWRIGHT_CONFIG_ROOT/config.v2.json
$SPACEWRIGHT_CONFIG_ROOT/generated/spacewright.skhdrc
$SPACEWRIGHT_STATE_ROOT/machine.json
```

The first two files are portable user configuration. `machine.json` contains
only local display-role-to-UUID bindings and should not be synced between Macs.

Saving uses a same-directory temporary file and atomic rename. If the target
already exists, the previous content is copied to a `.backup` file first.

The configurator never reads or writes a Mackup checkout, the user's complete
`skhdrc`, displayplacer profiles, or yabai configuration. The generated skhd
fragment is inert until the user explicitly integrates it with skhd.

## Editor model

- **Apps** map portable app keys to one or more macOS application names.
- **Display roles** describe portable intent. UUID bindings belong in
  `$SPACEWRIGHT_STATE_ROOT/machine.json` under `displayBindings`. The Displays
  page can discover connected displays read-only and bind a UUID to a role on
  the current Mac.
- **Workspaces** have a human name, stable label prefix, window roles, and
  solo/wide/tall variants.
- **Layouts** use recursive row/column split trees. The compiler converts them
  into deterministic yabai grids. Migrated v1 configurations may retain an
  exact canvas/grid representation.
- **Modes** assign an ordered workspace lane to each display role. Lane order
  controls both Space order and execution order.
- **Shortcuts** reference a closed set of SpaceWright actions; arbitrary shell
  commands are not accepted.

Saving configuration does not move windows, create Spaces, apply display
profiles, or reload skhd. Live changes still require an explicit workspace or
display command.

Saving validates the complete document and writes both `config.v2.json` and a
digest-bound `generated/runtime.json`. Import validates external JSON as an
unsaved preview. Export downloads the portable document. Restore Backup
revalidates and recompiles the previous saved document before activating it.
The service also keeps the 10 most recent prior portable documents under
`$SPACEWRIGHT_CONFIG_ROOT/backups`; machine-local state is never included.

The Apps page can perform read-only discovery of application names reported by
yabai. Workspace roles expose every supported selector, and Review presents
non-fatal semantic warnings alongside the exact compiled plan.

The Workspaces page includes a visual 12 by 12 layout editor. Choose a preset
as a starting point or select **Edit freely**, then drag windows to move them
and drag the lower-right handle to resize them. The window inspector provides
exact Left, Top, Width, and Height values for keyboard input. Adding an app
window places it in the current layout; removing one also removes its placement
from every mode variant. The application registry remains available from the
same inspector when a new macOS application name is needed.
Presets cover left/right, top/bottom, both one-third ratios, either side split
into rows, and either top or bottom region split into columns. Three-window
rows and columns, a four-window grid, and main-plus-three layouts cover larger
workspace sets.

The editor warns before closing with unsaved changes. Renaming an application,
display role, workspace, or window role updates its structured references.
Deletion requires confirmation and is rejected while the object is still in
use. Mode ordering supports both drag-and-drop and keyboard-operable up/down
buttons. Drop slots allow exact insertion between existing workspaces, while
the display selector on each card supports moving across displays without a
mouse. An Unassigned lane lists workspaces excluded from the selected mode.
The footer reports whether the draft is saved and provides bounded Undo and
Redo history. Standard Command/Ctrl-Z and Command/Ctrl-Shift-Z shortcuts work
outside text-entry controls, where the browser's native text undo remains in
charge. Dialogs trap focus, close with Escape, and return focus to the editor.

## Apply, history, and recovery

Apply first computes a path-level diff and asks for confirmation. The server
validates the candidate, snapshots the previous configuration, writes the
compiled runtime and source atomically, reads the source back from disk, and
fails the request if it differs. A verified configuration receives a second
snapshot. **Revert changes** discards only the current unsaved edit, while
**Reset to SpaceWright defaults** loads the product starter configuration as an
unsaved preview. History entries can be compared, renamed, restored, or
deleted. Restore itself creates a recovery snapshot first.

Every loaded document carries a content revision. Save and diff requests send
that revision back, and the server rejects a stale draft instead of overwriting
an external edit. Reloading is then required so the external version can be
reviewed explicitly.

## Profiles, automation, and workspace preview

Optional `profiles`, `rules`, and `settings` sections extend the v2 contract.
A profile selects a `solo`, `wide`, or `tall` mode and can narrow activation to
named workspaces. Closed optional fields select a `solo`, `wide_left`, or
`tall_left` display profile, a final workspace to focus, and whether one bounded
reconciliation retry is allowed.
Rules are closed declarative records: supported events are display connect,
display disconnect, topology change, wake, and manual activation. Conditions
may match app, workspace, display, layout, orientation, or one of these
topologies: `solo`, `wide_left`, `wide_right`, `tall_left`, `tall_right`,
`dual_external`, and `clamshell`. Actions can activate only a declared profile
or workspace; arbitrary shell is not accepted.

The Current state and Profiles & rules pages expose a dry-run plan from a fresh
display, Space, and window snapshot. They show blockers, changes, warnings, and
the closed runner sequence without launching applications, creating Spaces,
focusing a window, or changing a display. The Current state page can also
capture one live Space into an unsaved canvas-layout draft.

The Run & tasks page is the browser execution control surface. Modes,
profiles, and individual workspace variants can be previewed, explicitly
confirmed, started, monitored, and cancelled. The server maps each request to
closed `spacewright apply` arguments; request data is never interpreted as a
shell command. Runs are serialized, process-group cancellation is supported,
and each apply writes a durable state journal. Execution output is streamed
into the current server session's task record and the rotating durable activity
log records task start and completion. Running is available only for the exact
plan, configuration digest, and desktop snapshot returned by the latest
preview. If any of them changes, execution fails closed and the user must
preview again. In-memory task history and per-task output are bounded so a
long-running configurator session cannot grow without limit.

Topology rules can be evaluated without mutation from the browser. Setting
`settings.eventAutomationEnabled` to `true` opts into five-second topology
monitoring while the configurator service is running. A transition must remain
stable for `topologyStableSamples` observations and pass the
`topologyCooldownSeconds` cooldown before it can run a matching rule. Query
failure is reported as unknown rather than solo. `spacewright event wake`
delivers the wake event to the running service. Automation is off by default
and stops when the configurator process exits.

## Diagnostics and portable configuration

Diagnostics reports yabai availability, the accessibility/query path, detected
displays and topology, display binding health, duplicate labels, compiled
runtime freshness, build identity, the authenticated local backend, schema
validity, and configured workspaces. Scripting-addition readiness is explicitly
shown as not verified because a read-only query cannot prove mutation support. The report can be
copied or exported, and the self-test performs validation and compilation
without desktop mutation. Successful saves, restores, and self-tests appear in
the local activity log under the SpaceWright state directory.

Import accepts JSON or YAML, validates it before replacing the editor model,
and keeps it unsaved until Apply. Export produces `spacewright.yaml`. JSON
remains fully supported and existing v2 files do not require the new optional
sections.

## Configuration data flow

The portable v2 file is the authoritative configuration source:

```text
$SPACEWRIGHT_CONFIG_ROOT/config.v2.json
  -> configurator service readConfig()
  -> GET /api/config
  -> Configuration GUI state

Configuration GUI state
  -> POST /api/validate and POST /api/save
  -> validateV2() and atomicWrite()
  -> $SPACEWRIGHT_CONFIG_ROOT/config.v2.json
```

The service reads the file for every `GET /api/config`; it does not keep a
configuration cache. The GUI reads the API when the page loads, validates the
complete in-memory document before saving, and writes only a valid v2 document.
After an external file edit, reload the page to fetch the authoritative value;
the revision check prevents a stale open page from silently replacing it.
Restarting the configurator does not affect persistence because the JSON file,
not the server process, owns the state.

Machine-local display bindings follow the same pattern through `GET
/api/machine` and `POST /api/display-bindings`, with
`$SPACEWRIGHT_STATE_ROOT/machine.json` as their separate authoritative source.

The browser integration test uses a temporary real config root, starts the
actual configurator service, edits a reversible display name in Chromium,
checks the JSON file directly, verifies page reload and service restart, applies
an external file edit, and restores the original document. No API or config
backend is mocked.

## Read-only CLI

```fish
spacewright config-v2-check
spacewright config-v2-compile
spacewright config-compile
spacewright config-migrate-v1 ~/.config/spacewright/config.json
```

Migration prints v2 JSON to standard output and does not overwrite its input.
It preserves existing workspace commands, labels, per-variant window lists,
runner adapters, layout actions, aggregate cleanup, and trusted mode
postprocessors. The user chooses whether and where to save the result.

Opening `configurator/public/index.html` directly shows a read-only sample for
design review. Saving, display discovery, machine binding, and skhd generation
require `spacewright configure` so that the loopback service can validate and
write the correct user-owned files.

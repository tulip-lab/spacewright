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

The editor warns before closing with unsaved changes. Renaming an application,
display role, workspace, or window role updates its structured references.
Deletion requires confirmation and is rejected while the object is still in
use. Mode ordering supports both drag-and-drop and keyboard-operable up/down
buttons.

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
After an external file edit, reload the page to fetch the authoritative value.
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

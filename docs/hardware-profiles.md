# Hardware profiles and display setups

SpaceWright v3 separates portable intent into three layers:

```text
hardware profile -> connected-display setup -> workspace configuration
```

A hardware profile represents a Mac family, not one physical computer. Two
MacBooks therefore share the same `macbook` profile. Physical display UUIDs,
Sidecar classification, and topology confirmations remain in the local
`machine.json` and are never part of the portable file.

## First-time setup

Create or migrate a v3 document, then detect the current Mac without changing
the desktop:

```fish
spacewright config-migrate-v2 ~/.config/spacewright/config.v2.json > ~/.config/spacewright/config.v3.json
spacewright setup detect
spacewright setup status
```

The Web Configurator's **Hardware & Setups** page provides the same workflow.
It detects the model family and connected displays, lets the user mark an
external display as Sidecar when macOS/yabai does not expose that distinction,
and proposes every matching setup.

Confirm the selected profile and setup once:

```fish
spacewright setup confirm mac_mini single_tall
```

Confirmation writes only machine-local state. SpaceWright records the current
topology signature, display-role bindings, and selected setup, then compiles a
digest-bound runtime. A new or ambiguous topology must be confirmed before any
mutation; unavailable display discovery also fails closed.

After confirmation, normal commands resolve the setup automatically:

```fish
spacewright plan coding
spacewright workspace coding --dry-run
spacewright workspace coding
```

No configuration or mode argument is needed for routine v3 workspace use.

## Portable model

`config.v3.json` contains:

- `hardwareProfiles`: shared `macbook`, `mac_mini`, or `other` family profiles;
- `setups`: named display combinations under each profile;
- `match.displays`: required display kind and optional orientation/role;
- `lanes`: workspace ordering by portable display role;
- `workspaceConfigurations`: the named configuration selected for every
  workspace placed by that setup;
- `workspaces.*.configurations`: reusable layouts and bounded runtime options.

The built-in starter includes these Mac mini setups:

- `single_wide`
- `single_tall`
- `wide_tall`
- `wide_sidecar`
- `tall_sidecar`

The MacBook starter includes built-in-only, built-in + wide/tall, built-in +
Sidecar, and built-in + wide/tall + Sidecar setups.

Additional setups, including two wide or two tall displays, can be created by
duplicating a nearby setup in the Configurator and changing its display match,
lanes, and workspace assignments.

Sidecar is explicit because it is a semantic kind, not merely an orientation.
A Sidecar setup can therefore select a different workspace configuration from
an otherwise similar external-display setup.

## Workspace configurations

A workspace has stable windows and identity plus any number of named
configurations. For example, `coding` might define `laptop`, `wide`, and
`tall`. Each hardware setup explicitly chooses one:

```json
{
  "workspaceConfigurations": {
    "coding": "tall"
  }
}
```

Configurations can use the same split-tree and exact 12×12 canvas layouts as
v2 variants. The v3 compiler projects the active setup into the existing
deterministic v2 execution engine, preserving the validated plan, preflight,
apply, and verification behavior.

## Resolution and safety

At command time SpaceWright:

1. reads the Mac model family;
2. queries displays through yabai;
3. applies local Sidecar classifications and role bindings;
4. computes a topology key from display kinds and orientations;
5. selects the previously confirmed setup;
6. resolves each workspace's named configuration;
7. validates and compiles the projected runtime.

The command stops before mutation if the profile is unmatched, multiple setups
remain possible, the topology has not been confirmed, a display query fails,
or any workspace/configuration reference is invalid.

The authoritative structural contract is
[`spacewright-v3.schema.json`](../schemas/spacewright-v3.schema.json), with a
portable starting point in [`config-v3.json`](../examples/config-v3.json).

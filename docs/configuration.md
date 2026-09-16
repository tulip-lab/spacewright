# Configuration

## Roots

SpaceWright loads package defaults from `config/defaults.json` and optionally
merges a user file from:

```text
$SPACEWRIGHT_CONFIG_FILE
```

when explicitly set, otherwise:

```text
$SPACEWRIGHT_CONFIG_ROOT/config.json
```

`SPACEWRIGHT_CONFIG_ROOT` follows `XDG_CONFIG_HOME` and falls back to
`~/.config/spacewright`.

Objects merge recursively and user arrays replace package arrays. This lets a
consumer override one app or workspace without copying unrelated defaults.

## Read-Only Commands

```fish
workspace_config_check
workspace_config_get coding_editor_wide
workspace_config_plan coding_editor_wide
workspace_config_plan coding_wide
```

These commands validate or render configuration only. They do not query or
change live desktop state.

`coding_editor_wide` is the first configured runtime pilot. Its default output
matches the legacy definition, and `SPACEWRIGHT_CONFIG_DISABLE=1` switches that
entry back to the built-in legacy path for rollback.

Before the configured runner performs cleanup or creates a Space, it verifies
that the required primary app window exists. A failed preflight returns
non-zero without changing workspace state.

## Version 1 Boundary

Configuration owns:

- app keys and accepted macOS app names;
- workspace labels and display roles;
- required and optional window roles;
- explainable window selection flags;
- reusable layout actions;
- mode membership and simple cleanup policy.

Configuration does not accept shell commands, jq expressions, loops,
conditionals, retries, or service-control actions.

The authoritative schema is
[`schemas/spacewright.schema.json`](../schemas/spacewright.schema.json). A
minimal override is available at [`examples/config.json`](../examples/config.json).

## Example Workspace

```json
{
  "version": 1,
  "workspaces": {
    "coding_editor_wide": {
      "label": "coding_editor_wide",
      "display_role": "wide",
      "space_layout": "float",
      "windows": [
        {
          "role": "primary",
          "app_key": "code",
          "required": true,
          "selector": { "movable": true, "visible": true }
        }
      ],
      "layout_ref": "single_full"
    }
  }
}
```

User overrides are merged with package defaults, so replacing a whole existing
workspace requires supplying every field required by that workspace object.

## Validation

`workspace_config_check` validates the effective configuration and cross-checks
app keys, layout references, workspace references, and the supported v1
enumerations. Invalid configuration returns non-zero before any configured
runtime path may mutate state.

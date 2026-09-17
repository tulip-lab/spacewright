# Configuration

## Configuration versions

The Web Configurator writes the portable v2 document to:

```text
$SPACEWRIGHT_CONFIG_ROOT/config.v2.json
```

When that file exists, SpaceWright validates and deterministically compiles it
to the normalized runtime plan consumed by Fish. v2 models logical workspaces,
per-mode layout variants, display lanes, recursive split trees, and structured
shortcuts. See [Web Configurator](configurator.md) and the authoritative
[`spacewright-v2.schema.json`](../schemas/spacewright-v2.schema.json).

v1 remains supported for compatibility. SpaceWright never silently rewrites a
v1 file. `spacewright config-migrate-v1` prints a proposed v2 document without
writing it. Migration retains each variant's exact window list, runner options,
layout actions and cleanup behavior, then flattens trusted nested mode steps
while preserving their order and postprocessor anchors.

Machine-local display UUID bindings are deliberately separate from both
configuration versions:

```text
$SPACEWRIGHT_STATE_ROOT/machine.json
```

The portable config names display roles; this local state maps those roles to
the UUIDs reported by yabai on one Mac.

## Version 1 roots

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
If `config.v2.json` is present it takes precedence over this v1 merge path.

## Read-Only Commands

```fish
workspace_config_check
workspace_config_get coding_editor_wide
workspace_config_plan coding_editor_wide
workspace_config_plan coding_wide
```

These commands validate or render configuration only. They do not query or
change live desktop state.

Every shipped workspace and aggregate solo/wide/tall mode has a configuration
entry. This includes coding, research, Office writing/slides, GTD support,
review, mail, meeting, AI, chat, calendar, and coding control. Their configured
dry-run output is regression-tested against the imported legacy definition.

`SPACEWRIGHT_CONFIG_DISABLE=1` switches all entries back to the imported Fish
definitions for rollback without changing public command names.

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

Mode steps are ordered because shared windows such as ChatGPT are intentionally
owned by the last applicable workspace. A mode step can reference a configured
workspace, one of a small closed set of nested modes, or one of the two trusted
postprocessors used by the imported runtime.

Top-level `work_solo`, `work_wide`, and `work_tall` modes own the complete
cross-family cleanup set. Nested modes suppress their own cleanup while an
aggregate is running, so the outer mode removes empty labels belonging to the
two inactive display modes before and after its ordered steps.

Configuration does not accept shell commands, jq expressions, loops,
conditionals, retries, or service-control actions.

Runner names are also a closed enum. Generic primary/helper workspaces use the
shared configured runner. Office and recovery-heavy GTD workspaces use trusted
Fish adapters that consume configured labels, display roles, apps, layouts,
and cleanup relationships while retaining their bounded recovery algorithms.

The authoritative schema is
[`schemas/spacewright.schema.json`](../schemas/spacewright.schema.json). A
minimal override is available at [`examples/config.json`](../examples/config.json).

## Example Workspace

```json
{
  "version": 1,
  "workspaces": {
    "coding_editor_wide": {
      "runner": "primary_helper",
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

## Runtime And Observation

```fish
workspace_run_configured coding_editor_wide --dry-run
workspace_run_configured_mode work_wide --dry-run
workspace_plan --json coding_editor_wide
workspace_verify --json coding_editor_wide
workspace_verify --all --json
```

Observation contracts are generated from the same effective configuration.
`--all` selects fixed workspaces plus the solo/wide/tall variants appropriate
for the detected display mode, avoiding false drift from inactive variants.

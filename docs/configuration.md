# Configuration

## Configuration versions

The Web Configurator writes the portable v2 document to:

```text
$SPACEWRIGHT_CONFIG_ROOT/config.v2.json
```

Every successful save also atomically produces:

```text
$SPACEWRIGHT_CONFIG_ROOT/generated/runtime.json
```

The generated document records the SHA-256 of the canonical portable source.
Fish uses it only while that digest matches `config.v2.json`, so it never
silently runs a stale plan. Normal workspace commands therefore do not require
Node.js after configuration has been compiled. `spacewright config-compile`
performs the same compilation without opening the Web Configurator.

Generated metadata includes the runtime format, compiler version, source
configuration version, source digest, and deterministic generation id. A
runtime with an unsupported metadata version is treated as stale.

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

## Version 2 Contract

The JSON Schema is the structural contract. Runtime validation adds semantic
checks: references must resolve, Space label prefixes must be unique, required
window roles must occur in each layout, a workspace may occur only once in a
mode, and shortcut chords must be unique. Unused variants and unplaced optional
windows are reported as warnings.

Window selectors use one read-only yabai snapshot before any mutation. They
support `movable`, `visible`, `non_empty_title`, `title_include`, and
`title_exclude`, plus AX `role` and `subrole`. Application definitions may add
bundle identifiers as a stronger identity signal; app-name aliases remain the
portable fallback because standard yabai snapshots do not expose bundle IDs.
One window cannot satisfy two roles in the same workspace.

Each window role may declare `ownership: "lastApplicable"` (the default) or
`"independent"` for selector-separated windows from the same app, plus
`cardinality: "one"` (the default) or `"many"` for adaptive layouts. A variant
may declare `activation: { "type": "always" }` or
`activation: { "type": "windowPresent", "role": "primary" }`. Migration emits
the latter for Office document adapters and marks GTD Support's Dia role as
multi-window. The Web Configurator exposes these settings under Window
Matching / Advanced.

`aiProviders` maps a human AI identity such as Hermes or ChatGPT to a registered
application. `aiRouting.assignments` then maps one semantic window role in a
workspace to a default provider. That default is shared by Solo, Wide, and Tall;
an assignment's `overrides` object contains only deliberate per-mode provider
exceptions. `roleOverrides` supports a legacy variant whose equivalent AI slot
uses a different role name. The compiler replaces the concrete app in that role
and derives one contextual ownership rule per active provider.

`aiRouting.fallbackWorkspace` is the deterministic home for a provider that is
not selected by the workspace focused before a mode transition. When
`focusOwner` is true, the source-matched AI workspace receives final focus;
otherwise the first fallback does. This lets different workspaces use different
AI providers in the same mode without moving either provider through every
workspace. Existing mode-level `contextualApps` rules remain supported for
non-AI or compatibility policies and may now contain more than one app.

The stable user command is `spacewright run <workspace-id>
<solo|wide|tall>`. Imported `variant.command` values preserve historical Fish
commands; generated `spacewright_<id>_<mode>` identifiers remain internal.

Runner names are also a closed enum. Generic primary/helper workspaces use the
shared configured runner. Office and recovery-heavy GTD workspaces use trusted
Fish adapters that consume configured labels, display roles, apps, layouts,
and cleanup relationships while retaining their bounded recovery algorithms.

The authoritative v2 schema is
[`schemas/spacewright-v2.schema.json`](../schemas/spacewright-v2.schema.json). A
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
spacewright config-compile
spacewright config-status
spacewright config-diff
spacewright config-explain coding wide
spacewright inspect
spacewright plan coding wide
spacewright verify coding wide
spacewright capture captured_coding wide
```

`config-status` reports source and runtime freshness as JSON. `config-diff`
compiles a temporary candidate and compares it with the saved runtime without
changing either file. `config-explain` resolves a logical workspace and mode
to its normalized read-only execution plan. `inspect`, live `plan`, `verify`, and
`capture` are read-only state-engine commands; see
[State discovery and reconciliation](state-reconciliation.md).

Observation contracts are generated from the same effective configuration.
`--all` selects fixed workspaces plus the solo/wide/tall variants appropriate
for the detected display mode, avoiding false drift from inactive variants.

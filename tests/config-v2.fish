#!/usr/bin/env fish

set -l test_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $test_file))
set -l test_root (mktemp -d /private/tmp/spacewright-config-v2-test.XXXXXX)

command node "$package_root/configurator/cli.mjs" starter > "$test_root/config.v2.json"
or exit 1

set -e SPACEWRIGHT_PACKAGE_ROOT
set -e SPACEWRIGHT_ROOT
set -gx SPACEWRIGHT_CONFIG_ROOT "$test_root"
source "$package_root/conf.d/spacewright.fish"
or exit 2

workspace_config_check
or exit 3

set -l plan (workspace_config_plan spacewright_coding_wide | string collect)
or exit 4
printf "%s\n" "$plan" | jq -e '
    .kind == "workspace"
    and .runner == "generic_layout"
    and .display_role == "task__wide"
    and .layout == [
        {"role":"assistant","grid":"120:120:0:0:40:120"},
        {"role":"editor","grid":"120:120:40:0:80:120"}
    ]
' >/dev/null
or exit 5

set -l dry_run (workspace_run_configured spacewright_coding_wide --dry-run | string collect)
or exit 6
string match -q '*grid=editor:120:120:40:0:80:120*' -- "$dry_run"
or exit 7

command node "$package_root/configurator/cli.mjs" migrate-v1 "$package_root/config/defaults.json" > "$test_root/migrated.json"
or exit 8
command node "$package_root/configurator/cli.mjs" validate "$test_root/migrated.json"
or exit 9
command node "$package_root/configurator/cli.mjs" compile "$test_root/migrated.json" > "$test_root/migrated-runtime.json"
or exit 10

jq -n -e \
    --slurpfile original "$package_root/config/defaults.json" \
    --slurpfile migrated "$test_root/migrated-runtime.json" '
    ($original[0].workspaces | keys) == ($migrated[0].workspaces | keys)
    and ([ $original[0].workspaces | keys[] as $id |
        $original[0].layouts[$original[0].workspaces[$id].layout_ref]
        == $migrated[0].layouts[$migrated[0].workspaces[$id].layout_ref]
    ] | all)
    and (def expand($root; $id): [$root.modes[$id].steps[] |
        if has("mode") then expand($root; .mode)[] else . end];
        ["solo", "wide", "tall"] as $modes | all($modes[]; . as $mode |
            expand($original[0]; "work_" + $mode) == $migrated[0].modes["work_" + $mode].steps
            and ($original[0].modes["work_" + $mode].cleanup // []) == $migrated[0].modes["work_" + $mode].cleanup
        ))
' >/dev/null
or exit 11

cp "$test_root/migrated.json" "$test_root/config.v2.json"
workspace_config_check
or exit 12

for workspace_id in (jq -r '.workspaces | keys[]' "$test_root/migrated-runtime.json")
    workspace_config_plan "$workspace_id" >/dev/null
    or exit 13
    mv "$test_root/config.v2.json" "$test_root/config.v2.hold"
    set -l v1_dry_run (workspace_run_configured "$workspace_id" --dry-run 2>&1 | string collect)
    set -l v1_status $pipestatus[1]
    mv "$test_root/config.v2.hold" "$test_root/config.v2.json"
    set -l v2_dry_run (workspace_run_configured "$workspace_id" --dry-run 2>&1 | string collect)
    set -l v2_status $pipestatus[1]
    if test "$v2_status" != "$v1_status"
        echo "dry-run status mismatch for $workspace_id: v1=$v1_status v2=$v2_status" >&2
        exit 14
    end
    if test "$v2_dry_run" != "$v1_dry_run"
        echo "dry-run output mismatch for $workspace_id" >&2
        exit 15
    end
end

mkdir -p "$test_root/state"
printf '%s\n' '{"version":1,"displayBindings":{"task":"DISPLAY-TASK-1234"}}' > "$test_root/state/machine.json"
set -gx SPACEWRIGHT_STATE_ROOT "$test_root/state"
function ws_query_displays
    printf '%s\n' '[{"index":1,"uuid":"DISPLAY-PRIMARY-1","frame":{"w":1512,"h":982}},{"index":2,"uuid":"DISPLAY-TASK-1234","frame":{"w":2560,"h":1440}}]'
end
test (workspace_resolve_display_role task__wide) = 2
or exit 16

echo "OK      v2 schema, split compiler, migrated Fish dry-runs, modes, and machine bindings"

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

command node "$package_root/configurator/cli.mjs" compile-to "$test_root/config.v2.json" "$test_root/generated/runtime.json"
or exit 18
test (jq -r '.generated.source_sha256 | length' "$test_root/generated/runtime.json") -eq 64
or exit 19
jq -e '.generated.format_version == 1 and .generated.compiler_version == 3 and .generated.source_version == 2 and (.generated.generation_id | length) == 16' "$test_root/generated/runtime.json" >/dev/null
or exit 24
spacewright_config_status | jq -e '.version == 2 and .current == true and (.generation_id | length) == 16' >/dev/null
or exit 25
mv "$test_root/generated/runtime.json" "$test_root/generated/runtime.hold"
spacewright_config_status | jq -e '.version == 2 and .current == false and .generation_id == ""' >/dev/null
test $pipestatus[1] -eq 1
or exit 28
mv "$test_root/generated/runtime.hold" "$test_root/generated/runtime.json"
spacewright_config_effective | jq -e '.source_version == 2 and (has("generated") | not)' >/dev/null
or exit 20
set -l original_path $PATH
set -l no_node_bin "$test_root/no-node-bin"
mkdir -p "$no_node_bin"
ln -s (command -s jq) "$no_node_bin/jq"
ln -s (command -s shasum) "$no_node_bin/shasum"
set -gx PATH "$no_node_bin"
spacewright_config_effective | "$no_node_bin/jq" -e '.source_version == 2' >/dev/null
or exit 23
set -gx PATH $original_path

set -l selector_plan '{"windows":[{"app_names":["Code"],"selector":{"movable":true,"visible":true,"non_empty_title":true,"title_include":"Project","title_exclude":"Ignore"}}]}'
set -l selector_windows '[{"id":10,"app":"Code","title":"Ignore Project","is-minimized":false,"is-visible":true,"can-move":true},{"id":11,"app":"Code","title":"Project Alpha","is-minimized":false,"is-visible":true,"can-move":true},{"id":12,"app":"Code","title":"Project Beta","is-minimized":false,"is-visible":true,"can-move":true}]'
test (__workspace_config_select_window "$selector_windows" "$selector_plan" 0) = 11
or exit 21
test (__workspace_config_select_window "$selector_windows" "$selector_plan" 0 11) = 12
or exit 22

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

set -g __generic_query_count 0
function workspace_config_plan
    printf '%s\n' '{"kind":"workspace","id":"spacewright_demo_wide","runner":"generic_layout","label":"demo_wide","display_role":"task__wide","space_layout":"float","windows":[{"role":"primary","app_key":"code","required":true,"app_names":["Code"],"selector":{"movable":true}}],"layout":[{"role":"primary","grid":"1:1:0:0:1:1"}],"runner_options":{},"cleanup":null,"mutates":false}'
end
function ws_query_windows
    set -g __generic_query_count (math $__generic_query_count + 1)
    if test $__generic_query_count -eq 1
        printf '%s\n' '[{"id":42,"app":"Code","title":"Demo","is-minimized":false,"is-visible":true,"can-move":true,"space":1}]'
    else
        printf '%s\n' '[{"id":42,"app":"Code","title":"Demo","is-minimized":false,"is-visible":true,"can-move":true,"space":9}]'
    end
end
function workspace_resolve_display_role; echo 2; end
function workspace_prepare_labeled_space; echo 9; end
function ws_move_windows_to_space; return 0; end
function ws_window; return 0; end
workspace_run_configured spacewright_demo_wide
or exit 26
test "$__generic_query_count" -eq 2
or exit 33

set -g __generic_fullscreen_toggle ""
function ws_query_windows
    set -l phase $argv[2]
    switch "$phase"
        case all
            printf '%s\n' '[{"id":42,"app":"Code","title":"Demo","is-minimized":false,"is-visible":true,"is-native-fullscreen":true,"can-move":false,"space":1}]'
        case native_fullscreen_1
            printf '%s\n' '[{"id":42,"app":"Code","title":"Demo","is-minimized":false,"is-visible":true,"is-native-fullscreen":false,"can-move":true,"space":1}]'
        case 'final_*'
            printf '%s\n' '[{"id":42,"app":"Code","title":"Demo","is-minimized":false,"is-visible":true,"is-native-fullscreen":false,"can-move":true,"space":9}]'
        case '*'
            return 1
    end
end
function ws_window
    if test "$argv[2]" = --toggle
        set -g __generic_fullscreen_toggle (string join " " -- $argv)
    end
end
workspace_run_configured spacewright_demo_wide
or exit 29
test "$__generic_fullscreen_toggle" = "42 --toggle native-fullscreen"
or exit 30

function workspace_config_plan
    printf '%s\n' '{"kind":"workspace","id":"spacewright_demo_wide","runner":"generic_layout","label":"demo_wide","display_role":"task__wide","space_layout":"float","windows":[{"role":"primary","app_key":"code","required":true,"app_names":["Code"],"selector":{"movable":true}},{"role":"helper","app_key":"chatgpt","required":false,"app_names":["ChatGPT"],"selector":{"movable":true}}],"layout":[{"role":"primary","grid":"1:1:0:0:1:1"},{"role":"helper","grid":"1:1:0:0:1:1"}],"runner_options":{},"cleanup":null,"mutates":false}'
end
set -g __generic_fullscreen_toggle ""
function ws_query_windows
    printf '%s\n' '[{"id":43,"app":"ChatGPT","title":"Helper","is-minimized":false,"is-visible":true,"is-native-fullscreen":true,"can-move":false,"space":1}]'
end
workspace_run_configured spacewright_demo_wide >/dev/null 2>&1
and exit 31
test -z "$__generic_fullscreen_toggle"
or exit 32

set -g __generic_query_count 0
function ws_query_windows
    set -g __generic_query_count (math $__generic_query_count + 1)
    if test "$argv[2]" = all
        printf '%s\n' '[{"id":42,"app":"Code","title":"Demo","is-minimized":false,"is-visible":true,"is-native-fullscreen":false,"can-move":true,"space":1}]'
    else
        printf '%s\n' '[{"id":42,"app":"Code","title":"Demo","is-minimized":false,"is-visible":true,"is-native-fullscreen":false,"can-move":true,"space":9}]'
    end
end
workspace_run_configured spacewright_demo_wide
or exit 34
test "$__generic_query_count" -eq 2
or exit 35

function workspace_config_plan
    printf '%s\n' '{"kind":"workspace","id":"spacewright_demo_wide","runner":"generic_layout","label":"demo_wide","display_role":"task__wide","space_layout":"float","windows":[{"role":"primary","app_key":"code","required":true,"app_names":["Code"],"selector":{"movable":true}}],"layout":[{"role":"primary","grid":"1:1:0:0:1:1"}],"runner_options":{},"cleanup":null,"mutates":false}'
end
set -g __generic_query_count 0
function ws_query_windows
    set -g __generic_query_count (math $__generic_query_count + 1)
    printf '%s\n' '[{"id":42,"app":"Code","title":"Demo","is-minimized":false,"is-visible":true,"can-move":true,"space":1}]'
end
workspace_run_configured spacewright_demo_wide >/dev/null 2>&1
and exit 27

set -g __primary_helper_find_count 0
function workspace_run_cleanup_specs; return 0; end
function workspace_find_app_key_window
    set -g __primary_helper_find_count (math $__primary_helper_find_count + 1)
    echo 42
end
function ws_query_windows
    printf '%s\n' '[{"id":42,"app":"Code","title":"Demo","is-minimized":false,"is-visible":true,"is-native-fullscreen":false,"can-move":true,"space":9}]'
end
function ws_focus_space; return 0; end
function cleanup_unlabeled_empty_spaces; return 0; end
workspace_apply_primary_helper_space \
    --label demo_wide \
    --display task__wide \
    --primary-app-key code \
    --primary-window 42 \
    --primary-grid 1:1:0:0:1:1
or exit 41
test "$__primary_helper_find_count" -eq 1
or exit 42

set -g __primary_helper_find_count 0
set -g __primary_helper_apply_args
function workspace_config_plan
    printf '%s\n' '{"kind":"workspace","id":"primary_helper_demo","runner":"primary_helper","label":"demo_wide","display_role":"task__wide","space_layout":"float","windows":[{"role":"primary","app_key":"code","required":true,"app_names":["Code"],"selector":{"movable":true}}],"layout":[{"role":"primary","grid":"1:1:0:0:1:1"}],"primary_alone_layout":[],"runner_options":{},"cleanup":null}'
end
function workspace_apply_primary_helper_space
    set -g __primary_helper_apply_args $argv
end
workspace_run_configured primary_helper_demo
or exit 43
test "$__primary_helper_find_count" -eq 1
or exit 44
contains -- --primary-window $__primary_helper_apply_args
or exit 45
set -l primary_window_arg_index (math (contains --index -- --primary-window $__primary_helper_apply_args) + 1)
test "$__primary_helper_apply_args[$primary_window_arg_index]" = 42
or exit 46

set -g __nested_cleanup_count 0
function workspace_config_plan
    printf '%s\n' '{"kind":"mode","id":"nested_mode","cleanup":["office:wide","office:solo"],"steps":[{"workspace":"nested_test_step"}],"contextual_apps":[]}'
end
function workspace_run_cleanup_specs
    set -g __nested_cleanup_count (math $__nested_cleanup_count + 1)
end
function nested_test_step
    return 0
end
set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1
workspace_run_configured_mode nested_mode >/dev/null
or exit 36
workspace_run_mode_steps office:wide -- nested_test_step >/dev/null
or exit 37
test "$__nested_cleanup_count" -eq 0
or exit 38
set -e WORKSPACE_SKIP_LABELED_CLEANUP
workspace_run_configured_mode nested_mode >/dev/null
or exit 39
test "$__nested_cleanup_count" -eq 2
or exit 40

echo "OK      v2 schema, split compiler, migrated Fish dry-runs, modes, and machine bindings"

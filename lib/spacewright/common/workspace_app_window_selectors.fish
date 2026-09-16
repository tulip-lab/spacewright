function workspace_select_app_window --description "Select a window id for an app from yabai windows JSON on stdin"
    argparse 'app=' 'space=' movable visible -- $argv
    or return 1

    if not set -q _flag_app
        echo "usage: workspace_select_app_window --app <app-name> [--space <space>] [--movable] [--visible]" >&2
        return 1
    end

    set -l movable 0
    set -l visible 0
    set -l target_space ""

    if set -q _flag_movable
        set movable 1
    end

    if set -q _flag_visible
        set visible 1
    end

    if set -q _flag_space
        set target_space $_flag_space
    end

    if test "$WORKSPACE_DEBUG_SELECT" = "1"
        workspace_debug_step workspace_select_app_window read-start app=$_flag_app
    end

    set -l windows_json
    read -lz windows_json

    if test "$WORKSPACE_DEBUG_SELECT" = "1"
        workspace_debug_step workspace_select_app_window read-done app=$_flag_app bytes=(string length -- "$windows_json")
        workspace_debug_step workspace_select_app_window jq-start app=$_flag_app
    end

    set -l window_id (echo $windows_json | ws_jq -r \
        --arg app "$_flag_app" \
        --arg target_space "$target_space" \
        --arg movable "$movable" \
        --arg visible "$visible" \
        '
        first(
            .[]
            | select(.app==$app)
            | select(.["is-minimized"]==false)
            | select(($target_space=="") or (.space==($target_space | tonumber)))
            | select(($movable!="1") or (.["can-move"]==true))
            | select(($visible!="1") or (.["is-visible"]==true))
            | .id
        ) // empty
        '
    )
    set -l jq_status $status

    if test "$WORKSPACE_DEBUG_SELECT" = "1"
        workspace_debug_step workspace_select_app_window jq-done app=$_flag_app status=$jq_status window=$window_id
    end

    if test "$jq_status" -ne 0
        return $jq_status
    end

    if test -n "$window_id"
        echo $window_id
    end
end

function workspace_app_key_window_info --description "Return first non-minimized app-key window metadata from yabai window JSON on stdin"
    argparse 'app-key=' movable unmovable -- $argv
    or return 1

    if not set -q _flag_app_key
        echo "usage: workspace_app_key_window_info --app-key <key> [--movable|--unmovable]" >&2
        return 2
    end

    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        return 1
    end

    set -l apps_json (workspace_app_names_json $_flag_app_key)
    or return 1

    set -l movable_filter ""
    if set -q _flag_movable
        set movable_filter movable
    else if set -q _flag_unmovable
        set movable_filter unmovable
    end

    echo $windows_json | ws_jq -r --argjson apps "$apps_json" --arg movable_filter "$movable_filter" '
        first(
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.["is-minimized"]==false)
            | select(
                if $movable_filter == "movable" then
                    .["can-move"]==true
                elif $movable_filter == "unmovable" then
                    .["can-move"]!=true
                else
                    true
                end
            )
            | [.id, .space, .display, .["can-move"]]
            | @tsv
        ) // empty
    '
end

function workspace_app_key_windows --description "Return matching app-key window ids from yabai window JSON"
    argparse 'app-key=' 'space=' 'not-space=' movable unmovable visible nonempty-title not-native-fullscreen -- $argv
    or return 1

    if not set -q _flag_app_key
        echo "usage: workspace_app_key_windows --app-key <key> [--space <space>] [--not-space <space>] [--movable|--unmovable] [--visible] [--nonempty-title] [--not-native-fullscreen]" >&2
        return 2
    end

    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        return 1
    end

    set -l apps_json (workspace_app_names_json $_flag_app_key)
    or return 1

    set -l space "$_flag_space"
    set -l not_space "$_flag_not_space"
    set -l movable_filter ""
    set -l visible 0
    set -l nonempty_title 0
    set -l not_native_fullscreen 0

    if set -q _flag_movable
        set movable_filter movable
    else if set -q _flag_unmovable
        set movable_filter unmovable
    end

    if set -q _flag_visible
        set visible 1
    end

    if set -q _flag_nonempty_title
        set nonempty_title 1
    end

    if set -q _flag_not_native_fullscreen
        set not_native_fullscreen 1
    end

    echo $windows_json | ws_jq -r \
        --argjson apps "$apps_json" \
        --arg space "$space" \
        --arg not_space "$not_space" \
        --arg movable_filter "$movable_filter" \
        --arg visible "$visible" \
        --arg nonempty_title "$nonempty_title" \
        --arg not_native_fullscreen "$not_native_fullscreen" '
        .[]
        | select(.app as $app | $apps | index($app))
        | select(.["is-minimized"]==false)
        | select(($visible!="1") or (.["is-visible"]==true))
        | select(($nonempty_title!="1") or (.title != null and .title != ""))
        | select(($not_native_fullscreen!="1") or (.["is-native-fullscreen"]!=true))
        | select(
            if $movable_filter == "movable" then
                .["can-move"]==true
            elif $movable_filter == "unmovable" then
                .["can-move"]!=true
            else
                true
            end
        )
        | select(($space=="") or (.space==($space | tonumber)))
        | select(($not_space=="") or (.space!=($not_space | tonumber)))
        | .id
    '
end

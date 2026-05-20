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

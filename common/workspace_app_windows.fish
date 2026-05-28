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

function workspace_refresh_app_window --description "Find an app window, activating the app once if needed"
    argparse 'app=' 'caller=' 'space=' movable visible -- $argv
    or return 1

    if not set -q _flag_app
        echo "usage: workspace_refresh_app_window --app <app-name> [--caller <name>] [--space <space>] [--movable] [--visible]" >&2
        return 1
    end

    set -l caller workspace_refresh_app_window
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l selector_args --app "$_flag_app"

    if set -q _flag_space
        set -a selector_args --space $_flag_space
    end

    if set -q _flag_movable
        set -a selector_args --movable
    end

    if set -q _flag_visible
        set -a selector_args --visible
    end

    workspace_debug_step $caller refresh-$_flag_app-query-initial
    set -l windows_json (ws_query_windows "$caller" app_refresh_initial); or return 1
    set -l window_id (echo $windows_json | workspace_select_app_window $selector_args)
    if test $status -ne 0
        return 1
    end

    if test -n "$window_id"
        workspace_debug_step $caller refresh-$_flag_app-found-initial $window_id
        echo $window_id
        return 0
    end

    set -l app_present (echo $windows_json | workspace_select_app_window --app "$_flag_app")
    if test $status -ne 0
        return 1
    end

    if test -z "$app_present"
        workspace_debug_step $caller refresh-$_flag_app-not-present
        return 0
    end

    workspace_debug_step $caller refresh-$_flag_app-open
    perl -e 'alarm shift; exec @ARGV' 2 open -a "$_flag_app" >/dev/null 2>&1
    sleep 0.4

    workspace_debug_step $caller refresh-$_flag_app-query-after-open
    set windows_json (ws_query_windows "$caller" app_refresh_after_open); or return 1
    set window_id (echo $windows_json | workspace_select_app_window $selector_args)
    if test $status -ne 0
        return 1
    end

    if test -n "$window_id"
        workspace_debug_step $caller refresh-$_flag_app-found-after-open $window_id
        echo $window_id
        return 0
    end

    workspace_debug_step $caller refresh-$_flag_app-unavailable
    return 2
end

function workspace_find_app_window --description "Find a movable app window, activating the app once if needed"
    argparse 'app=' 'caller=' 'space=' 'attempts=' 'wait=' no-refresh visible -- $argv
    or return 1

    if not set -q _flag_app
        echo "usage: workspace_find_app_window --app <app-name> [--caller <name>] [--space <space>] [--no-refresh] [--visible]" >&2
        return 1
    end

    set -l caller workspace_find_app_window
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l attempts 4
    if set -q _flag_attempts
        set attempts $_flag_attempts
    end

    set -l wait_seconds 0.5
    if set -q _flag_wait
        set wait_seconds $_flag_wait
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l selector_args --app "$_flag_app" --movable
    set -l app_key (string replace -ra '[^A-Za-z0-9]+' '_' -- "$_flag_app")

    if set -q _flag_visible
        set -a selector_args --visible
    end

    if set -q _flag_space
        workspace_debug_step $caller find-$app_key-target-query
        set -l phase find_{$app_key}_target
        set -l windows_json (ws_query_windows "$caller" $phase); or return 1
        set -l target_selector_args $selector_args --space $_flag_space
        set -l window_id (echo $windows_json | workspace_select_app_window $target_selector_args)

        if test -n "$window_id"
            workspace_debug_step $caller find-$app_key-target-found $window_id
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
            echo $window_id
            return 0
        end
    end

    if set -q _flag_no_refresh
        workspace_debug_step $caller find-$app_key-any-query
        set -l phase find_{$app_key}_any
        set -l windows_json (ws_query_windows "$caller" $phase); or return 1
        set -l window_id (echo $windows_json | workspace_select_app_window $selector_args)

        if test -n "$window_id"
            workspace_debug_step $caller find-$app_key-any-found $window_id
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
            echo $window_id
        end

        return 0
    end

    workspace_debug_step $caller find-$app_key-refresh-query-initial
    set -l phase find_{$app_key}_refresh_initial
    set -l windows_json (ws_query_windows "$caller" $phase); or return 1
    set -l window_id (echo $windows_json | workspace_select_app_window $selector_args)

    if test -n "$window_id"
        workspace_debug_step $caller find-$app_key-refresh-found-initial $window_id
        rm -f "$bad_window_dir/$window_id" 2>/dev/null
        echo $window_id
        return 0
    end

    set -l app_present (echo $windows_json | workspace_select_app_window --app "$_flag_app")
    if test -z "$app_present"
        workspace_debug_step $caller find-$app_key-not-present
        return 0
    end

    workspace_debug_step $caller find-$app_key-activate
    perl -e 'alarm shift; exec @ARGV' 2 open -a "$_flag_app" >/dev/null 2>&1

    for attempt in (seq 1 $attempts)
        sleep $wait_seconds
        workspace_debug_step $caller find-$app_key-refresh-query-after-activate-$attempt
        set phase find_{$app_key}_refresh_after_activate_$attempt
        set windows_json (ws_query_windows "$caller" $phase); or return 1
        set window_id (echo $windows_json | workspace_select_app_window $selector_args)

        if test -n "$window_id"
            workspace_debug_step $caller find-$app_key-refresh-found-after-activate $window_id
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
            echo $window_id
            return 0
        end
    end

    workspace_debug_step $caller find-$app_key-refresh-unmovable
    echo "[WARN] $caller found $_flag_app, but yabai did not expose a movable $_flag_app window" >&2
    return 2
end

function workspace_capture_app_window --description "Move a movable app window to a target space and confirm it landed there"
    argparse 'app=' 'caller=' 'space=' visible -- $argv
    or return 1

    if not set -q _flag_app; or not set -q _flag_space
        echo "usage: workspace_capture_app_window --app <app-name> --space <space> [--caller <name>] [--visible]" >&2
        return 1
    end

    set -l caller workspace_capture_app_window
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l find_args --app "$_flag_app" --caller "$caller"
    if set -q _flag_visible
        set -a find_args --visible
    end

    set -l window_id (workspace_find_app_window $find_args)
    set -l find_status $status

    if test "$find_status" -eq 1
        return 1
    end

    if test -n "$window_id"
        ws_move_windows_to_space $_flag_space $window_id
    else if test "$find_status" -eq 2
        return 2
    end

    set -l target_window (workspace_find_app_window $find_args --space $_flag_space --no-refresh)
    if test -n "$target_window"
        echo $target_window
        return 0
    end

    set window_id (workspace_find_app_window $find_args --space $_flag_space)
    set find_status $status

    if test "$find_status" -eq 1
        return 1
    end

    if test -n "$window_id"
        ws_move_windows_to_space $_flag_space $window_id
        set target_window (workspace_find_app_window $find_args --space $_flag_space --no-refresh)

        if test -n "$target_window"
            echo $target_window
            return 0
        end
    end

    if test "$find_status" -eq 2
        return 2
    end

    return 0
end

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

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
    argparse 'app=' 'caller=' 'space=' 'attempts=' 'wait=' no-refresh target-only visible quiet-unmovable -- $argv
    or return 1

    if not set -q _flag_app
        echo "usage: workspace_find_app_window --app <app-name> [--caller <name>] [--space <space>] [--no-refresh] [--target-only] [--visible]" >&2
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

        if set -q _flag_target_only
            workspace_debug_step $caller find-$app_key-target-missing
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

    set -l app_present_space (echo $windows_json | ws_jq -r --arg app "$_flag_app" '
        first(
            .[]
            | select(.app==$app)
            | select(.["is-minimized"]==false)
            | .space
        ) // empty
    ')

    if test -n "$app_present_space"
        workspace_debug_step $caller find-$app_key-focus-present-space $app_present_space
        ws_focus_space $app_present_space >/dev/null 2>&1
        sleep 0.2

        set phase find_{$app_key}_after_present_space_focus
        set windows_json (ws_query_windows "$caller" $phase); or return 1
        set window_id (echo $windows_json | workspace_select_app_window $selector_args)

        if test -n "$window_id"
            workspace_debug_step $caller find-$app_key-found-after-present-space-focus $window_id
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
            echo $window_id
            return 0
        end
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
    if not set -q _flag_quiet_unmovable
        echo "[WARN] $caller found $_flag_app, but yabai did not expose a movable $_flag_app window" >&2
    end
    return 2
end

function workspace_find_app_key_window --description "Find a movable app window using all registered names for an app key"
    argparse 'app-key=' 'caller=' 'space=' 'attempts=' 'wait=' no-refresh target-only visible quiet-unmovable -- $argv
    or return 1

    if not set -q _flag_app_key
        echo "usage: workspace_find_app_key_window --app-key <key> [--caller <name>] [--space <space>] [--no-refresh] [--target-only] [--visible]" >&2
        return 1
    end

    set -l caller workspace_find_app_key_window
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l app_names (workspace_app_names $_flag_app_key)
    or return 1

    set -l attempts 4
    if set -q _flag_attempts
        set attempts $_flag_attempts
    end

    set -l wait_seconds 0.5
    if set -q _flag_wait
        set wait_seconds $_flag_wait
    end

    set -l saw_unmovable 0

    for app_name in $app_names
        set -l find_args --app "$app_name" --caller "$caller"

        if set -q _flag_space
            set -a find_args --space $_flag_space
        end

        if set -q _flag_attempts
            set -a find_args --attempts $_flag_attempts
        end

        if set -q _flag_wait
            set -a find_args --wait $_flag_wait
        end

        if set -q _flag_no_refresh
            set -a find_args --no-refresh
        end

        if set -q _flag_target_only
            set -a find_args --target-only
        end

        if set -q _flag_visible
            set -a find_args --visible
        end

        if set -q _flag_quiet_unmovable
            set -a find_args --quiet-unmovable
        end

        set -l window_id (workspace_find_app_window $find_args)
        set -l find_status $status

        if test "$find_status" -eq 1
            return 1
        end

        if test -n "$window_id"
            echo $window_id
            return 0
        end

        if test "$find_status" -eq 2
            set saw_unmovable 1
        end
    end

    if test "$saw_unmovable" -eq 1
        if not set -q _flag_no_refresh
            workspace_debug_step $caller find-$_flag_app_key-activate-canonical $app_names[1]
            perl -e 'alarm shift; exec @ARGV' 2 open -a "$app_names[1]" >/dev/null 2>&1

            for attempt in (seq 1 $attempts)
                sleep $wait_seconds

                for app_name in $app_names
                    set -l retry_find_args --app "$app_name" --caller "$caller" --no-refresh

                    if set -q _flag_space
                        set -a retry_find_args --space $_flag_space
                    end

                    if set -q _flag_visible
                        set -a retry_find_args --visible
                    end

                    if set -q _flag_target_only
                        set -a retry_find_args --target-only
                    end

                    if set -q _flag_quiet_unmovable
                        set -a retry_find_args --quiet-unmovable
                    end

                    set -l window_id (workspace_find_app_window $retry_find_args)
                    set -l find_status $status

                    if test "$find_status" -eq 1
                        return 1
                    end

                    if test -n "$window_id"
                        echo $window_id
                        return 0
                    end
                end
            end
        end

        for app_name in $app_names
            set -l final_find_args --app "$app_name" --caller "$caller" --no-refresh

            if set -q _flag_space
                set -a final_find_args --space $_flag_space
            end

            if set -q _flag_visible
                set -a final_find_args --visible
            end

            if set -q _flag_target_only
                set -a final_find_args --target-only
            end

            if set -q _flag_quiet_unmovable
                set -a final_find_args --quiet-unmovable
            end

            set -l window_id (workspace_find_app_window $final_find_args)
            set -l find_status $status

            if test "$find_status" -eq 1
                return 1
            end

            if test -n "$window_id"
                echo $window_id
                return 0
            end
        end

        return 2
    end

    return 0
end

function workspace_capture_app_window --description "Move a movable app window to a target space and confirm it landed there"
    argparse 'app=' 'app-key=' 'caller=' 'space=' visible -- $argv
    or return 1

    if not set -q _flag_app; and not set -q _flag_app_key
        echo "usage: workspace_capture_app_window --app <app-name>|--app-key <key> --space <space> [--caller <name>] [--visible]" >&2
        return 1
    end

    if not set -q _flag_space
        echo "usage: workspace_capture_app_window --app <app-name>|--app-key <key> --space <space> [--caller <name>] [--visible]" >&2
        return 1
    end

    set -l caller workspace_capture_app_window
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l find_args --caller "$caller"
    set -l find_command workspace_find_app_window
    if set -q _flag_app_key
        set find_command workspace_find_app_key_window
        set -a find_args --app-key $_flag_app_key
    else
        set -a find_args --app "$_flag_app"
    end

    if set -q _flag_visible
        set -a find_args --visible
    end

    set -l window_id ($find_command $find_args)
    set -l find_status $status

    if test "$find_status" -eq 1
        return 1
    end

    if test -n "$window_id"
        ws_move_windows_to_space $_flag_space $window_id
    else if test "$find_status" -eq 2
        return 2
    end

    set -l target_window ($find_command $find_args --space $_flag_space --no-refresh --target-only)
    if test -n "$target_window"
        echo $target_window
        return 0
    end

    set window_id ($find_command $find_args --space $_flag_space)
    set find_status $status

    if test "$find_status" -eq 1
        return 1
    end

    if test -n "$window_id"
        ws_move_windows_to_space $_flag_space $window_id
        set target_window ($find_command $find_args --space $_flag_space --no-refresh --target-only)

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

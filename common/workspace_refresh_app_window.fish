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

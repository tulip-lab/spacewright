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

function gtd_find_outlook_window --description "Find a movable Microsoft Outlook window, activating Outlook once if needed"
    set -l caller $argv[1]
    set -l target_space $argv[2]
    set -l mode $argv[3]

    if test -z "$caller"
        set caller gtd_meeting
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l out

    if test -n "$target_space"
        workspace_debug_step $caller outlook-target-query
        set -l windows_json (ws_query_windows "$caller" outlook_target); or return 1
        set out (echo $windows_json | workspace_select_app_window --app "Microsoft Outlook" --space $target_space --movable)

        if test -n "$out"
            workspace_debug_step $caller outlook-target-found $out
            rm -f "$bad_window_dir/$out" 2>/dev/null
            echo $out
            return 0
        end
    end

    if test "$mode" = "--no-refresh"
        workspace_debug_step $caller outlook-any-query
        set -l windows_json (ws_query_windows "$caller" outlook_any); or return 1
        set out (echo $windows_json | workspace_select_app_window --app "Microsoft Outlook" --movable)

        if test -n "$out"
            workspace_debug_step $caller outlook-any-found $out
            rm -f "$bad_window_dir/$out" 2>/dev/null
            echo $out
        end

        return 0
    end

    workspace_debug_step $caller outlook-refresh
    set out (workspace_refresh_app_window --app "Microsoft Outlook" --caller "$caller" --movable)
    set -l outlook_status $status

    if test -n "$out"
        workspace_debug_step $caller outlook-refresh-found $out
        rm -f "$bad_window_dir/$out" 2>/dev/null
        echo $out
        return 0
    end

    if test "$outlook_status" -eq 0
        return 0
    end

    if test "$outlook_status" -eq 1
        return 1
    end

    workspace_debug_step $caller outlook-refresh-unmovable
    echo "[WARN] $caller found Microsoft Outlook, but yabai did not expose a movable Outlook window" >&2
    return 2
end

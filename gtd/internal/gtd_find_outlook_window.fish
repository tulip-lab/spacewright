function gtd_find_outlook_window --description "Find a movable Microsoft Outlook window through the shared app-window helper"
    set -l caller $argv[1]
    set -l target_space $argv[2]
    set -l mode $argv[3]

    if test -z "$caller"
        set caller gtd_meeting
    end

    set -l find_args --app (workspace_app_name outlook) --caller "$caller"

    if test -n "$target_space"
        set -a find_args --space $target_space
    end

    if test "$mode" = "--no-refresh"
        set -a find_args --no-refresh
    end

    workspace_find_app_window $find_args
    set -l find_status $status

    if test "$find_status" -eq 2
        echo "[HINT] If Outlook stays non-movable, run: yabai --restart-service" >&2
    end

    return $find_status
end

function gtd_find_chatgpt_window --description "Find a movable ChatGPT window through the shared app-window helper"
    set -l caller $argv[1]
    set -l target_space $argv[2]
    set -l mode $argv[3]

    if test -z "$caller"
        set caller gtd_review
    end

    set -l find_args --app ChatGPT --caller "$caller"

    if test -n "$target_space"
        set -a find_args --space $target_space
    end

    if test "$mode" = "--no-refresh"
        set -a find_args --no-refresh
    end

    workspace_find_app_window $find_args
end

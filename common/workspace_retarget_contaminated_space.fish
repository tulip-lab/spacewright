function workspace_retarget_contaminated_space --description "Return a clean labeled target space, clearing a contaminated label when needed"
    set -l caller $argv[1]
    set -l label $argv[2]
    set -l target_space $argv[3]
    set -l target_display $argv[4]
    set -l allowed_app_regex $argv[5]

    if test -z "$caller" -o -z "$label" -o -z "$target_space" -o -z "$target_display" -o -z "$allowed_app_regex"
        return 1
    end

    set -l windows_json (ws_query_windows "$caller" target_check); or return 1
    set -l non_owned_window_count (echo $windows_json | ws_jq -r \
        --argjson s $target_space \
        --arg allowed_app_regex "$allowed_app_regex" '
        [
            .[]
            | select(.space==$s)
            | select((.app | test($allowed_app_regex)) | not)
        ]
        | length
    ')

    if test -z "$non_owned_window_count"
        return 1
    end

    if test "$non_owned_window_count" -gt 0
        workspace_debug_step $caller retarget-contaminated-space count=$non_owned_window_count
        ws_yabai -m space $target_space --label "" >/dev/null 2>&1
        set target_space (find_or_create_labeled_space $label $target_display)

        if test -z "$target_space"
            return 1
        end
    end

    echo $target_space
end

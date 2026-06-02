function workspace_space_non_owned_windows --description "Return window ids on a space whose app is outside an allowed app regex"
    argparse 'space=' 'allowed-app-regex=' movable unmovable -- $argv
    or return 1

    if not set -q _flag_space; or not set -q _flag_allowed_app_regex
        echo "usage: workspace_space_non_owned_windows --space <space> --allowed-app-regex <regex> [--movable|--unmovable]" >&2
        return 2
    end

    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        return 1
    end

    set -l movable_filter ""
    if set -q _flag_movable
        set movable_filter movable
    else if set -q _flag_unmovable
        set movable_filter unmovable
    end

    echo $windows_json | ws_jq -r \
        --argjson s $_flag_space \
        --arg allowed_app_regex "$_flag_allowed_app_regex" \
        --arg movable_filter "$movable_filter" '
        .[]
        | select(.space==$s)
        | select((.app | test($allowed_app_regex)) | not)
        | select(
            if $movable_filter == "movable" then
                .["can-move"]==true
            elif $movable_filter == "unmovable" then
                .["can-move"]!=true
            else
                true
            end
        )
        | .id
    '
end

function workspace_evict_non_owned_windows_from_space --description "Move movable non-owned windows out of an app-owned fallback space"
    argparse 'caller=' 'space=' 'target-display=' 'allowed-app-regex=' -- $argv
    or return 1

    if not set -q _flag_space; or not set -q _flag_target_display; or not set -q _flag_allowed_app_regex
        echo "usage: workspace_evict_non_owned_windows_from_space --space <space> --target-display <display> --allowed-app-regex <regex> [--caller <name>]" >&2
        return 2
    end

    set -l caller workspace_evict_non_owned_windows_from_space
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l windows_json (ws_query_windows "$caller" fallback_ownership); or return 1
    set -l movable_non_owned_windows (echo $windows_json | workspace_space_non_owned_windows \
        --space $_flag_space \
        --allowed-app-regex "$_flag_allowed_app_regex" \
        --movable)
    if test $status -ne 0
        return 1
    end

    set -l unmovable_non_owned_windows (echo $windows_json | workspace_space_non_owned_windows \
        --space $_flag_space \
        --allowed-app-regex "$_flag_allowed_app_regex" \
        --unmovable)
    if test $status -ne 0
        return 1
    end

    if test (count $unmovable_non_owned_windows) -gt 0
        echo "[WARN] $caller found non-owned unmovable fallback windows on space $_flag_space: "(string join , $unmovable_non_owned_windows) >&2
    end

    if test (count $movable_non_owned_windows) -eq 0
        return 0
    end

    set -l holding_space (workspace_create_unlabeled_space_on_display $_flag_target_display)
    if test -z "$holding_space"
        return 1
    end

    workspace_debug_step $caller evict-non-owned-fallback-windows count=(count $movable_non_owned_windows) holding_space=$holding_space
    ws_move_windows_to_space $holding_space $movable_non_owned_windows
    or return 1

    ws_focus_space $_flag_space >/dev/null 2>&1
end

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
    set -l non_owned_windows (echo $windows_json | workspace_space_non_owned_windows \
        --space $target_space \
        --allowed-app-regex "$allowed_app_regex")
    if test $status -ne 0
        return 1
    end

    set -l non_owned_window_count (count $non_owned_windows)

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

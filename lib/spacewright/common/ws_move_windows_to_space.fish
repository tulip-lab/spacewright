function ws_move_windows_to_space --description "Move multiple windows to a target space and refocus only when work was attempted"
    if test (count $argv) -lt 1
        return 1
    end

    set -l target_space $argv[1]
    set -e argv[1]

    if test -z "$target_space"
        return 1
    end

    if test (count $argv) -eq 0
        return 0
    end

    set -l attempted 0
    set -l requested_ids
    set -l move_failed 0

    for window_id in $argv
        if test -n "$window_id" -a "$window_id" != "null"
            set attempted 1
            if not contains -- $window_id $requested_ids
                set -a requested_ids $window_id
            end
            ws_window $window_id --space $target_space
            or set move_failed 1
        end
    end

    if test "$attempted" -eq 0
        return 0
    end

    for attempt in (seq 1 4)
        sleep 0.2
        set -l windows_json (ws_query_windows ws_move_windows_to_space confirm_$attempt)
        if test $status -eq 0 -a -n "$windows_json"
            set -l requested_json (printf '%s\n' $requested_ids | ws_jq -R 'tonumber' | ws_jq -s .)
            if echo $windows_json | ws_jq -e --argjson ids "$requested_json" --argjson target "$target_space" '
                . as $windows
                | all($ids[]; . as $id | any($windows[]; .id==$id and .space==$target))
            ' >/dev/null 2>&1
                ws_focus_space $target_space
                sleep 0.15
                return 0
            end
        end
    end

    if test "$move_failed" -eq 1
        echo "[WARN] one or more window move commands failed for Space $target_space" >&2
    else
        echo "[WARN] windows did not settle on Space $target_space: "(string join , -- $requested_ids) >&2
    end
    return 1
end

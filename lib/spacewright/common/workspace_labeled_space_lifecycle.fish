function find_or_create_labeled_space --description "Find an existing labeled space on target display or create and move one there"
    set -l label $argv[1]
    set -l target_display $argv[2]

    if test -z "$label"
        return 1
    end

    if test -z "$target_display"
        echo "[WARN] find_or_create_labeled_space: missing target display for label '$label'" >&2
        return 1
    end

    set -l spaces_json (ws_query_spaces find_or_create_labeled_space initial)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l existing_space_on_target (
        echo $spaces_json | ws_jq -r \
            --arg label "$label" \
            --argjson display "$target_display" \
            '.[]
             | select(.label==$label and .display==$display)
             | .index' | head -n 1
    )

    if test -n "$existing_space_on_target"
        echo $existing_space_on_target
        return 0
    end

    set -l stale_spaces (
        echo $spaces_json | ws_jq -r \
            --arg label "$label" \
            --argjson display "$target_display" \
            '.[]
             | select(.label==$label and .display!=$display and (.windows | length)==0)
             | .index'
    )

    for s in $stale_spaces
        ws_yabai -m space $s --destroy >/dev/null 2>&1
        sleep 0.2
    end

    set spaces_json (ws_query_spaces find_or_create_labeled_space after_stale_cleanup)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l windows_json (ws_query_windows find_or_create_labeled_space reusable_space)
    if test $status -ne 0 -o -z "$windows_json"
        return 1
    end

    set -l reusable_space (echo $spaces_json | ws_jq -r \
        --argjson display "$target_display" \
        --argjson windows "$windows_json" '
            [
                .[]
                | select(.display==$display)
                | select(.label=="")
                | select(.["is-visible"]!=true and .["has-focus"]!=true)
                | . as $space
                | select([
                    $windows[]
                    | select(.space==$space.index)
                    | select(.["is-sticky"]!=true)
                ] | length == 0)
            ]
            | sort_by(.index)
            | last
            | .index // empty
        ')
    or return 1

    if test -n "$reusable_space"
        echo $reusable_space
        return 0
    end

    set -l before_uuids (echo $spaces_json | ws_jq -r '.[].uuid')
    if test -z "$before_uuids"
        return 1
    end

    ws_yabai -m space --create >/dev/null 2>&1
    if test $status -ne 0
        return 1
    end

    set -l new_space_uuid ""
    for attempt in (seq 1 16)
        sleep 0.25
        set spaces_json (ws_query_spaces find_or_create_labeled_space after_create_$attempt)
        if test $status -ne 0 -o -z "$spaces_json"
            continue
        end

        set new_space_uuid (
            echo $spaces_json | ws_jq -r '.[].uuid' \
            | while read -l u
                if not contains -- $u $before_uuids
                    echo $u
                end
              end \
            | head -n 1
        )
        if test -n "$new_space_uuid"
            break
        end
    end

    if test -z "$new_space_uuid"
        echo "[WARN] find_or_create_labeled_space: yabai accepted Space creation but no new Space appeared; check scripting-addition compatibility" >&2
        return 1
    end

    set -l new_space_index (
            echo $spaces_json | ws_jq -r \
            --arg uuid "$new_space_uuid" \
            '.[]
             | select(.uuid==$uuid)
             | .index'
    )

    set -l new_space_display (
            echo $spaces_json | ws_jq -r \
            --arg uuid "$new_space_uuid" \
            '.[]
             | select(.uuid==$uuid)
             | .display'
    )

    if test -z "$new_space_index" -o -z "$new_space_display"
        return 1
    end

    if test "$new_space_display" != "$target_display"
        ws_yabai -m space $new_space_index --display $target_display >/dev/null 2>&1
        or begin
            echo "[WARN] find_or_create_labeled_space: could not move new Space to display $target_display" >&2
            return 1
        end
        sleep 0.8
    end

    set spaces_json (ws_query_spaces find_or_create_labeled_space final)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l final_space_index (
            echo $spaces_json | ws_jq -r \
            --arg uuid "$new_space_uuid" \
            --argjson display "$target_display" \
            '.[]
             | select(.uuid==$uuid and .display==$display)
             | .index'
    )

    if test -n "$final_space_index"
        echo $final_space_index
        return 0
    end

    echo "[WARN] find_or_create_labeled_space: new Space did not settle on display $target_display" >&2
    return 1
end

function workspace_create_unlabeled_space_on_display --description "Create an unlabeled holding space on the target display"
    set -l target_display $argv[1]

    if test -z "$target_display"
        echo "usage: workspace_create_unlabeled_space_on_display <target-display>" >&2
        return 2
    end

    set -l spaces_json (ws_query_spaces workspace_create_unlabeled_space_on_display holding_space_reuse)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l windows_json (ws_query_windows workspace_create_unlabeled_space_on_display holding_space_reuse)
    if test $status -ne 0 -o -z "$windows_json"
        return 1
    end

    set -l existing_empty_space (echo $spaces_json | ws_jq -r \
        --argjson display "$target_display" \
        --argjson windows "$windows_json" \
        'first(
            .[]
            | select(.display==$display)
            | select(.label=="")
            | . as $space
            | select(
                [
                    $windows[]
                    | select(.space==$space.index)
                    | select(.["is-sticky"]!=true)
                ]
                | length == 0
            )
            | .index
        ) // empty')

    if test -n "$existing_empty_space"
        echo $existing_empty_space
        return 0
    end

    set -l temp_label "__workspace_holding_"(date +%s)"_"$fish_pid
    set -l target_space (find_or_create_labeled_space $temp_label $target_display)
    if test -z "$target_space"
        return 1
    end

    ws_yabai -m space $target_space --label "" >/dev/null 2>&1

    set spaces_json (ws_query_spaces workspace_create_unlabeled_space_on_display holding_space_final)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set windows_json (ws_query_windows workspace_create_unlabeled_space_on_display holding_space_final)
    if test $status -ne 0 -o -z "$windows_json"
        return 1
    end

    set -l final_space_info (echo $spaces_json | ws_jq -r \
        --argjson target "$target_space" \
        --argjson windows "$windows_json" \
        'first(
            .[]
            | select(.index==$target)
            | [
                .label,
                (
                    [
                        $windows[]
                        | select(.space==$target)
                        | select(.["is-sticky"]!=true)
                    ]
                    | length
                )
            ]
            | @tsv
        ) // empty')

    if test -z "$final_space_info"
        return 1
    end

    set -l final_space_parts (string split \t -- "$final_space_info")
    set -l final_label $final_space_parts[1]
    set -l final_window_count $final_space_parts[2]

    if test -n "$final_label" -o "$final_window_count" != 0
        return 1
    end

    echo $target_space
end

function prepare_labeled_space --description "Normalize labeled space state"
    set -l target_space $argv[1]
    set -l label $argv[2]
    set -l layout $argv[3]

    if test -z "$target_space"
        return 1
    end

    if test -z "$layout"
        set layout float
    end

    if test -n "$label"
        set -l spaces_json (ws_query_spaces prepare_labeled_space label_ownership)
        if test $status -ne 0 -o -z "$spaces_json"
            return 1
        end

        set -l other_spaces (
            echo $spaces_json | ws_jq -r \
                --arg label "$label" \
                --argjson target "$target_space" \
                '.[]
                 | select(.label==$label and .index!=$target)
                 | .index'
        )

        for s in $other_spaces
            ws_yabai -m space $s --label "" >/dev/null 2>&1
        end

        ws_yabai -m space $target_space --label $label >/dev/null 2>&1
    end

    ws_yabai -m space $target_space --layout $layout >/dev/null 2>&1
end

function destroy_empty_labeled_space --description "Destroy the first empty space with the given label"
    set -l label $argv[1]

    if test -z "$label"
        return 1
    end

    set -l spaces_json (ws_query_spaces destroy_empty_labeled_space stale_check)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l stale_space (echo $spaces_json | ws_jq -r --arg label "$label" '
        .[]
        | select(.label==$label)
        | select((.windows | length) == 0)
        | .index
    ' | head -n 1)

    if test -n "$stale_space"
        ws_yabai -m space $stale_space --destroy >/dev/null 2>&1
    end
end

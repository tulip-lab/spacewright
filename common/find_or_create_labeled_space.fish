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

    # -------------------------------------------------------------------------
    # 1. Reuse only if the labeled space already exists on target display
    # -------------------------------------------------------------------------
    set -l spaces_json (ws_yabai -m query --spaces 2>/dev/null)
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

    # -------------------------------------------------------------------------
    # 2. Destroy empty same-label spaces stranded on other displays
    # -------------------------------------------------------------------------
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

    # -------------------------------------------------------------------------
    # 3. Record existing space UUIDs before creation
    # -------------------------------------------------------------------------
    set spaces_json (ws_yabai -m query --spaces 2>/dev/null)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l before_uuids (echo $spaces_json | ws_jq -r '.[].uuid')
    if test -z "$before_uuids"
        return 1
    end

    # -------------------------------------------------------------------------
    # 4. Create a new space
    # -------------------------------------------------------------------------
    ws_yabai -m space --create >/dev/null 2>&1
    if test $status -ne 0
        return 1
    end
    sleep 0.8

    # -------------------------------------------------------------------------
    # 5. Find the newly created space by UUID difference
    # -------------------------------------------------------------------------
    set spaces_json (ws_yabai -m query --spaces 2>/dev/null)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l new_space_uuid (
        echo $spaces_json | ws_jq -r '.[].uuid' \
        | while read -l u
            if not contains -- $u $before_uuids
                echo $u
            end
          end \
        | head -n 1
    )

    if test -z "$new_space_uuid"
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

    # -------------------------------------------------------------------------
    # 6. If created on the wrong display, move it explicitly
    # -------------------------------------------------------------------------
    if test "$new_space_display" != "$target_display"
        ws_yabai -m space $new_space_index --display $target_display >/dev/null 2>&1
        sleep 0.8
    end

    # -------------------------------------------------------------------------
    # 7. Re-resolve current index after possible move
    # -------------------------------------------------------------------------
    set spaces_json (ws_yabai -m query --spaces 2>/dev/null)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l final_space_index (
            echo $spaces_json | ws_jq -r \
            --arg uuid "$new_space_uuid" \
            '.[]
             | select(.uuid==$uuid)
             | .index'
    )

    if test -n "$final_space_index"
        echo $final_space_index
        return 0
    end

    return 1
end

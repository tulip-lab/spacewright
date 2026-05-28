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

    set spaces_json (ws_yabai -m query --spaces 2>/dev/null)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l before_uuids (echo $spaces_json | ws_jq -r '.[].uuid')
    if test -z "$before_uuids"
        return 1
    end

    ws_yabai -m space --create >/dev/null 2>&1
    if test $status -ne 0
        return 1
    end
    sleep 0.8

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

    if test "$new_space_display" != "$target_display"
        ws_yabai -m space $new_space_index --display $target_display >/dev/null 2>&1
        sleep 0.8
    end

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
        set -l spaces_json (ws_yabai -m query --spaces 2>/dev/null)
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

    set -l spaces_json (ws_yabai -m query --spaces 2>/dev/null)
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

function workspace_focus_labeled_space --description "Normalize and focus an existing labeled workspace space"
    set -l label $argv[1]
    set -l target_space $argv[2]
    set -l target_display $argv[3]
    set -l layout $argv[4]
    set -l cleanup_commands $argv[5..-1]

    if test -z "$label" -o -z "$target_space" -o -z "$target_display"
        echo "usage: workspace_focus_labeled_space <label> <target-space> <target-display> [layout] [cleanup-command ...]" >&2
        return 2
    end

    if test -z "$layout"
        set layout float
    end

    prepare_labeled_space $target_space $label $layout

    ws_focus_display $target_display
    sleep 0.15

    workspace_run_cleanup_specs $cleanup_commands
    or return 1

    ws_focus_space $target_space
    sleep 0.15
end

function workspace_prepare_labeled_space --description "Prepare and focus a labeled workspace space"
    set -l label $argv[1]
    set -l target_display $argv[2]
    set -l layout $argv[3]
    set -l cleanup_commands $argv[4..-1]

    if test -z "$label" -o -z "$target_display"
        echo "usage: workspace_prepare_labeled_space <label> <target-display> [layout] [cleanup-command ...]" >&2
        return 2
    end

    if test -z "$layout"
        set layout float
    end

    set -l target_space (find_or_create_labeled_space $label $target_display)
    if test -z "$target_space"
        return 1
    end

    workspace_focus_labeled_space $label $target_space $target_display $layout $cleanup_commands
    or return 1

    echo $target_space
end

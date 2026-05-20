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

    # -------------------------------------------------------------------------
    # If the same label is still attached to another space, clear it first.
    # This keeps label ownership explicit and stable.
    # -------------------------------------------------------------------------
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

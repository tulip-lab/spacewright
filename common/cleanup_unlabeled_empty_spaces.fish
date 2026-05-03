function cleanup_unlabeled_empty_spaces --description "Remove unlabeled empty spaces on target display except focused space"
    if test (count $argv) -lt 1
        return 0
    end

    set -l target_display $argv[1]
    set -l current_space (yabai -m query --spaces --space 2>/dev/null | jq -r '.index')

    if test -z "$target_display" -o -z "$current_space"
        return 0
    end

    set -l cleanup_spaces (yabai -m query --spaces 2>/dev/null | jq -r \
        --argjson display "$target_display" \
        --argjson current "$current_space" \
        '.[]
        | select(.display==$display)
        | select(.label=="")
        | select((.windows | length)==0)
        | select(.index!=$current)
        | .index')

    for s in $cleanup_spaces
        if test -n "$s"
            yabai -m space $s --destroy 2>/dev/null
            sleep 0.05
        end
    end
end
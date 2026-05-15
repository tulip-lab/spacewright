function cleanup_unlabeled_empty_spaces --description "Remove unlabeled empty spaces on all displays except a protected space"
    set -l protected_space $argv[1]

    if test -z "$protected_space"
        set protected_space (ws_yabai -m query --spaces --space 2>/dev/null | jq -r '.index')
    end

    if test -z "$protected_space"
        return 0
    end

    set -l cleanup_spaces (
        ws_yabai -m query --spaces 2>/dev/null | jq -r \
            --argjson protected "$protected_space" \
            '.[]
             | select(.label=="")
             | select((.windows | length)==0)
             | select(.index!=$protected)
             | .index' \
        | sort -nr
    )

    for s in $cleanup_spaces
        if test -n "$s"
            ws_yabai -m space $s --destroy >/dev/null 2>&1
            sleep 0.05
        end
    end
end

function cleanup_unlabeled_empty_spaces --description "Remove unlabeled empty spaces on all displays except a protected space"
    set -l protected_space $argv[1]

    if test -z "$protected_space"
        set -l current_space_json (ws_yabai -m query --spaces --space 2>/dev/null)
        if test $status -ne 0 -o -z "$current_space_json"
            return 0
        end

        set protected_space (echo $current_space_json | ws_jq -r '.index')
    end

    if test -z "$protected_space"
        return 0
    end

    set -l spaces_json (ws_yabai -m query --spaces 2>/dev/null)
    if test $status -ne 0 -o -z "$spaces_json"
        return 0
    end

    set -l cleanup_spaces (
        echo $spaces_json | ws_jq -r \
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

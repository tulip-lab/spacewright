function cleanup_labeled_empty_spaces --description "Destroy empty spaces whose labels match a regex"
    if test "$WORKSPACE_SKIP_LABELED_CLEANUP" = "1"
        return 0
    end

    set -l label_pattern $argv[1]
    set -l display_name $argv[2]

    if test -z "$label_pattern"
        return 1
    end

    if test -z "$display_name"
        set display_name "labeled"
    end

    set -l candidates (ws_yabai -m query --spaces | jq -r --arg pattern "$label_pattern" '
        [.[]
        | select(.label | test($pattern))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty $display_name space: $s"
        ws_yabai -m space $s --destroy >/dev/null 2>&1
    end
end

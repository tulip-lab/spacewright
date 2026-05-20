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

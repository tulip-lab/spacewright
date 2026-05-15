function workspace_mode_status_section --description "Print labeled spaces matching a mode regex"
    set -l title $argv[1]
    set -l label_pattern $argv[2]

    if test -z "$title" -o -z "$label_pattern"
        return 1
    end

    echo "===== $title ====="
    set -l spaces_json (ws_yabai -m query --spaces 2>/dev/null)
    if test $status -ne 0 -o -z "$spaces_json"
        echo "[WARN] workspace_mode_status_section could not query spaces from yabai" >&2
        return 1
    end

    echo $spaces_json | jq --arg pattern "$label_pattern" '
        .[]
        | select(.label | test($pattern))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
        }'
end

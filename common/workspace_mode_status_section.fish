function workspace_mode_status_section --description "Print labeled spaces matching a mode regex"
    set -l title $argv[1]
    set -l label_pattern $argv[2]

    if test -z "$title" -o -z "$label_pattern"
        return 1
    end

    echo "===== $title ====="
    yabai -m query --spaces | jq --arg pattern "$label_pattern" '
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

function coding_mode_status
    echo "===== CODING WIDE SPACES ====="
    yabai -m query --spaces | jq '
        .[]
        | select(.label | test("^coding_.*_wide$"))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
        }'

    echo
    echo "===== CODING TALL SPACES ====="
    yabai -m query --spaces | jq '
        .[]
        | select(.label | test("^coding_.*_tall$"))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
        }'

    echo
    echo "===== CODING INTERNAL SPACES ====="
    yabai -m query --spaces | jq '
        .[]
        | select(.label=="coding_control")
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
        }'
end
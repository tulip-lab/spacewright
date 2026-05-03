function coding_mode_status --description "Show coding spaces grouped by mode"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show current coding spaces grouped into:
    #     - wide mode spaces
    #     - tall mode spaces
    #     - internal fixed spaces
    #
    # Internal fixed spaces:
    #   - coding_control
    # -------------------------------------------------------------------------

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
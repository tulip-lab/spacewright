function office_mode_status --description "Show office spaces grouped by mode"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show current office spaces grouped into:
    #     - wide mode spaces
    #     - tall mode spaces
    # -------------------------------------------------------------------------

    echo "===== OFFICE WIDE SPACES ====="
    yabai -m query --spaces | jq '
        .[]
        | select(.label | test("^office_.*_wide$"))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
        }'

    echo
    echo "===== OFFICE TALL SPACES ====="
    yabai -m query --spaces | jq '
        .[]
        | select(.label | test("^office_.*_tall$"))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
        }'
end
function research_mode_status --description "Show research spaces grouped by mode"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show current research spaces grouped into:
    #     - wide mode spaces
    #     - tall mode spaces
    # -------------------------------------------------------------------------

    echo "===== RESEARCH WIDE SPACES ====="
    yabai -m query --spaces | jq '
        .[]
        | select((.label | test("^research.*_wide$")) or (.label == "research_wide"))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
        }'

    echo
    echo "===== RESEARCH TALL SPACES ====="
    yabai -m query --spaces | jq '
        .[]
        | select(.label | test("^research.*_tall$"))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
        }'
end
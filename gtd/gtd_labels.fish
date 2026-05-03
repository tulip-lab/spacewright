function gtd_labels --description "Show all current GTD space labels"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show all currently labeled GTD spaces.
    #
    # Notes:
    #   Only labels beginning with `gtd_` are included, so non-GTD labeled
    #   spaces from other workspace systems will not appear here.
    # -------------------------------------------------------------------------

    yabai -m query --spaces | jq '
        .[]
        | select(.label | test("^gtd_"))
        | {
            index,
            label,
            display
        }'
end
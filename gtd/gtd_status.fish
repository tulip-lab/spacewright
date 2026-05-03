function gtd_status --description "Show display, space and GTD application status"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show a full GTD status snapshot, including:
    #     - displays
    #     - spaces
    #     - GTD-related application windows
    #
    # Notes:
    #   The GTD application list is delegated to `gtd_apps` so the app filter
    #   is defined in one place only.
    # -------------------------------------------------------------------------

    echo "===== DISPLAYS ====="
    yabai -m query --displays | jq '.[] | {
        index,
        uuid,
        frame,
        has_focus: .["has-focus"],
        spaces
    }'

    echo
    echo "===== SPACES ====="
    yabai -m query --spaces | jq '.[] | {
        index,
        label,
        display,
        windows
    }'

    echo
    echo "===== GTD APPS ====="
    gtd_apps
end
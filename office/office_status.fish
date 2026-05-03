function office_status --description "Show display, space and office application status"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show a full office status snapshot, including:
    #     - displays
    #     - spaces
    #     - office-related application windows
    #
    # Covered office apps:
    #   - Microsoft Word
    #   - Microsoft PowerPoint
    #   - ChatGPT
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
    echo "===== OFFICE APPS ====="
    yabai -m query --windows | jq '
        .[]
        | select(
            .app=="Microsoft Word"
            or .app=="Microsoft PowerPoint"
            or .app=="ChatGPT"
        )
        | {
            id,
            app,
            title,
            space,
            is_visible: .["is-visible"],
            is_minimized: .["is-minimized"]
        }'
end
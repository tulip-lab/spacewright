function research_status --description "Show display, space and research application status"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show a full research status snapshot, including:
    #     - displays
    #     - spaces
    #     - research-related application windows
    #
    # Covered research apps:
    #   - Zotero
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
    echo "===== RESEARCH APPS ====="
    yabai -m query --windows | jq '
        .[]
        | select(
            .app=="Zotero"
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
function coding_status --description "Show display, space and coding application status"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show a full coding status snapshot, including:
    #     - displays
    #     - spaces
    #     - coding-related application windows
    #
    # Covered coding apps:
    #   - Code
    #   - ChatGPT
    #   - Warp
    #   - SmartGit
    #
    # Notes:
    #   Finder is intentionally excluded because it is not currently part of the
    #   rebuilt coding workspace layout set.
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
    echo "===== CODING APPS ====="
    yabai -m query --windows | jq '
        .[]
        | select(
            .app=="Code"
            or .app=="ChatGPT"
            or .app=="Warp"
            or .app=="SmartGit"
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
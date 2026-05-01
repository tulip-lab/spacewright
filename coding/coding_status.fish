function coding_status
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
            or .app=="Finder"
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
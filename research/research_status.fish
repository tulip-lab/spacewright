function research_status
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
        | select(.app=="Zotero")
        | {
            id,
            app,
            title,
            space,
            is_visible: .["is-visible"],
            is_minimized: .["is-minimized"]
        }'
end
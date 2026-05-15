function workspace_status_snapshot --description "Print common display and space status sections"
    echo "===== DISPLAYS ====="
    yabai -m query --displays | jq '.[] | {
        index,
        uuid,
        frame,
        has_focus: .["has-focus"],
        space_count: (.spaces | length),
        spaces
    }'

    echo
    echo "===== SPACES ====="
    yabai -m query --spaces | jq '.[] | {
        index,
        label,
        display,
        window_count: (.windows | length),
        windows
    }'
end

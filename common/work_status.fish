function work_status
    echo "===== DISPLAY ====="
    yabai -m query --displays | jq '.[] | {
        index,
        uuid,
        frame,
        has_focus: .["has-focus"],
        spaces
    }'

    echo
    echo "===== GTD ====="
    gtd_status

    echo
    echo "===== CODING ====="
    coding_status

    echo
    echo "===== OFFICE ====="
    office_status

    echo
    echo "===== RESEARCH ====="
    research_status
end
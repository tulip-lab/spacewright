function gtd_mode_status
    echo "===== GTD WIDE SPACES ====="
    yabai -m query --spaces | jq '.[] 
        | select(.label | test("^gtd_.*_wide$"))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
          }'

    echo
    echo "===== GTD TALL SPACES ====="
    yabai -m query --spaces | jq '.[] 
        | select(.label | test("^gtd_.*_tall$"))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
          }'

    echo
    echo "===== GTD INTERNAL SPACES ====="
    yabai -m query --spaces | jq '.[] 
        | select(.label=="gtd_chat" or .label=="gtd_calendar")
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
          }'
end
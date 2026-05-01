function gtd_status
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
    yabai -m query --windows | jq '
        .[]
        | select(
            .app=="Thunderbird"
            or .app=="Calendar"
            or .app=="Reminders"
            or .app=="Microsoft Outlook"
            or .app=="zoom.us"
            or .app=="Microsoft Teams"
            or .app=="WeChat"
            or .app=="Keybase"
            or .app=="DingTalk"
            or .app=="Messages"
            or .app=="WhatsApp"
            or .app=="ChatGPT"
            or .app=="Notes"
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
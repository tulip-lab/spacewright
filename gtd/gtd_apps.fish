function gtd_apps
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
            app,
            title,
            space,
            is_visible: .["is-visible"],
            is_minimized: .["is-minimized"]
        }'
end
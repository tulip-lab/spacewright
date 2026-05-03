function gtd_apps --description "Show all current GTD-related application windows"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show all application windows that currently belong to the GTD workspace
    #   system.
    #
    # Notes:
    #   This function is used as the canonical GTD app list for inspection and
    #   status reporting. Other GTD status helpers should reuse this function
    #   rather than duplicating the app filter list.
    #
    # Covered GTD apps:
    #   - Thunderbird
    #   - Calendar
    #   - Reminders
    #   - Microsoft Outlook
    #   - zoom.us
    #   - Microsoft Teams
    #   - WeChat
    #   - Keybase
    #   - DingTalk / 钉钉
    #   - Messages
    #   - WhatsApp
    #   - ChatGPT
    #   - Notes
    #   - Preview
    #   - Finder
    #   - Dia
    # -------------------------------------------------------------------------

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
            or .app=="钉钉"
            or .app=="Messages"
            or .app=="WhatsApp"
            or .app=="ChatGPT"
            or .app=="Notes"
            or .app=="Preview"
            or .app=="Finder"
            or .app=="Dia"
        )
        | {
            app,
            title,
            space,
            is_visible: .["is-visible"],
            is_minimized: .["is-minimized"]
        }'
end
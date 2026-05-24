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
    #   - Microsoft Teams / MSTeams
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

    set -l windows_json (ws_query_windows gtd_apps status); or return 1
    set -l bad_window_ids_json '[]'
    set -l bad_window_dir /tmp/workspace-ws-window-bad

    if test -d "$bad_window_dir"
        set -l bad_window_files (find "$bad_window_dir" -type f 2>/dev/null)
        set -l bad_window_ids

        for file in $bad_window_files
            set -l window_id (basename "$file")

            if string match -qr '^[0-9]+$' -- "$window_id"
                set -a bad_window_ids "$window_id"
            end
        end

        if test (count $bad_window_ids) -gt 0
            set bad_window_ids_json (printf '%s\n' $bad_window_ids | ws_jq -R . | ws_jq -s .)
        end
    end

    echo $windows_json | ws_jq --argjson bad_window_ids "$bad_window_ids_json" '
        .[]
        | select(
            .app=="Thunderbird"
            or .app=="Calendar"
            or .app=="Reminders"
            or .app=="Microsoft Outlook"
            or .app=="zoom.us"
            or .app=="Microsoft Teams"
            or .app=="MSTeams"
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
            id,
            app,
            title,
            space,
            display,
            is_visible: .["is-visible"],
            is_minimized: .["is-minimized"],
            can_move: .["can-move"],
            can_resize: .["can-resize"],
            has_ax_reference: .["has-ax-reference"],
            bad_window_cached: ((.id | tostring) as $id | ($bad_window_ids | index($id)) != null)
        }'
end

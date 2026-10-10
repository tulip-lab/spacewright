function workspace_ownership_policy_rows --description "Print static workspace app ownership policy rows"
    printf "%s\t%s\t%s\t%s\t%s\n" "coding_editor_*" "Code" "single-window" "required primary; first movable app-key window" code
    printf "%s\t%s\t%s\t%s\t%s\n" "coding_editor_wide/tall" "ChatGPT" "optional-helper" "single helper window when present; not launched when absent" chatgpt
    printf "%s\t%s\t%s\t%s\t%s\n" "coding_control" "Warp" "single-window" "optional control app; retargets contaminated labels" warp
    printf "%s\t%s\t%s\t%s\t%s\n" "coding_control" "SmartGit" "single-window;fallback-space-owner" "optional control app; current SmartGit space fallback" smartgit
    printf "%s\t%s\t%s\t%s\t%s\n" "coding_control" "KeePassXC/KeePassX" "single-window" "optional control app" keepassx
    printf "%s\t%s\t%s\t%s\t%s\n" "coding_control" "FlClash/Thaw" "all-movable-windows" "movable non-minimized windows; optional control app" "flclash thaw"
    printf "%s\t%s\t%s\t%s\t%s\n" "coding_control" "Portfolio Performance" "single-window" "optional control app" portfolio_performance

    printf "%s\t%s\t%s\t%s\t%s\n" "research_*" "Zotero" "single-window" "required primary; first movable app-key window" zotero
    printf "%s\t%s\t%s\t%s\t%s\n" "research_*" "Claude" "optional-helper" "single helper window when present; solo requires visibility" claude

    printf "%s\t%s\t%s\t%s\t%s\n" "office_writing_*" "Microsoft Word" "all-movable-windows" "required document windows; layout adapts to count" word
    printf "%s\t%s\t%s\t%s\t%s\n" "office_writing_*" "ChatGPT" "optional-helper" "single helper window when present" chatgpt
    printf "%s\t%s\t%s\t%s\t%s\n" "office_slides_*" "Microsoft PowerPoint" "all-movable-windows" "required document windows; layout adapts to count" powerpoint
    printf "%s\t%s\t%s\t%s\t%s\n" "office_slides_*" "ChatGPT" "optional-helper" "single helper window when present" chatgpt

    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_support_*" "Dia" "all-movable-windows" "exits native fullscreen, then collects all movable Dia windows" dia
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_review_*" "Finder" "all-movable-windows" "snapshot-first; reconciled from final window snapshot" finder
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_review_*" "Preview" "all-movable-windows;fallback-space-owner" "movable windows; non-movable Preview can own fallback space" preview
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_review_*" "Notes" "all-movable-windows;fallback-space-owner" "movable windows; non-movable Notes can own fallback space" notes
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_review_*" "ChatGPT" "optional-helper" "snapshot-first helper; capture only if existing window misses target" chatgpt
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_review_wide/tall" "Obsidian" "single-window" "optional existing window; not launched; no fallback-space ownership" obsidian
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_mail_*" "Thunderbird" "single-window;fallback-space-owner" "required primary; current space can become mail workspace" thunderbird
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_mail_*" "Microsoft Outlook" "optional-helper" "single helper window when present" outlook
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_meeting_*" "Zoom" "all-movable-windows;fallback-space-owner" "meeting/video/share windows; current Zoom space fallback" zoom
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_meeting_*" "Microsoft Teams/MSTeams" "all-movable-windows;fallback-space-owner" "meeting/video/call/share windows; non-movable companion space fallback" teams
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_ai" "Hermes" "single-window;fallback-space-owner" "primary AI window; current Hermes space fallback when non-movable; opened when missing" hermes
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_ai" "ChatGPT" "single-window" "first movable app-key window; opened when missing" chatgpt
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_ai" "Obsidian" "single-window" "first movable app-key window; opened when missing" obsidian
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_ai" "Notes" "single-window" "first movable app-key window; opened when missing" notes
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_chat" "WeChat" "single-window" "optional chat app; first movable app-key window" wechat
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_chat" "Keybase" "single-window" "optional chat app; first movable app-key window" keybase
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_chat" "DingTalk" "single-window;fallback-space-owner" "first app-key window; current space fallback when non-movable" dingtalk
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_chat" "Messages" "single-window" "optional chat app; first movable app-key window" messages
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_chat" "WhatsApp" "optional-helper" "single window; move failures tolerated" whatsapp
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_chat" "FaceTime" "single-window" "optional chat app; first movable app-key window; centered layout" facetime
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_calendar" "Calendar" "single-window;fallback-space-owner" "first app-key window; current space fallback when non-movable" calendar
    printf "%s\t%s\t%s\t%s\t%s\n" "gtd_calendar" "Reminders" "single-window" "first movable app-key window" reminders
end

function workspace_owned_app_keys --description "Print deduplicated app keys declared by workspace ownership policy"
    set -l keys
    for row in (workspace_ownership_policy_rows)
        set -l parts (string split \t -- "$row")
        if test (count $parts) -lt 5 -o -z "$parts[5]"
            echo "[WARN] workspace ownership row is missing app keys: $row" >&2
            return 1
        end

        for key in (string split ' ' -- $parts[5])
            workspace_app_names $key >/dev/null
            or return 1
            if not contains -- $key $keys
                set -a keys $key
            end
        end
    end
    printf "%s\n" $keys
end

function workspace_owned_app_names_json --description "Return all policy-owned yabai app names as JSON"
    set -l keys (workspace_owned_app_keys)
    or return 1
    workspace_app_names_json $keys
end

function workspace_print_ownership_policy --description "Print the static workspace app ownership policy table"
    printf "%-24s %-24s %-44s %s\n" "workspace" "app" "policy" "notes"

    workspace_ownership_policy_rows | while read -l row
        set -l parts (string split \t -- "$row")
        printf "%-24s %-24s %-44s %s\n" $parts[1] $parts[2] $parts[3] $parts[4]
    end
end

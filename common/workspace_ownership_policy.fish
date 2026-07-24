function workspace_ownership_policy_rows --description "Print static workspace app ownership policy rows"
    printf "%s\t%s\t%s\t%s\n" "coding_editor_*" "Code" "single-window" "required primary; first movable app-key window"
    printf "%s\t%s\t%s\t%s\n" "coding_editor_wide/tall" "ChatGPT" "optional-helper" "single helper window when present; not launched when absent"
    printf "%s\t%s\t%s\t%s\n" "coding_control" "Warp" "single-window" "optional control app; retargets contaminated labels"
    printf "%s\t%s\t%s\t%s\n" "coding_control" "SmartGit" "single-window;fallback-space-owner" "optional control app; current SmartGit space fallback"
    printf "%s\t%s\t%s\t%s\n" "coding_control" "KeePassXC/KeePassX" "single-window" "optional control app"
    printf "%s\t%s\t%s\t%s\n" "coding_control" "FlClash/Thaw" "all-movable-windows" "movable non-minimized windows; optional control app"

    printf "%s\t%s\t%s\t%s\n" "research_*" "Zotero" "single-window" "required primary; first movable app-key window"
    printf "%s\t%s\t%s\t%s\n" "research_solo" "ChatGPT" "optional-helper" "single visible helper window when present"
    printf "%s\t%s\t%s\t%s\n" "research_wide/tall" "Claude" "optional-helper" "single helper window when present"

    printf "%s\t%s\t%s\t%s\n" "office_writing_*" "Microsoft Word" "all-movable-windows" "required document windows; layout adapts to count"
    printf "%s\t%s\t%s\t%s\n" "office_writing_*" "ChatGPT" "optional-helper" "single helper window when present"
    printf "%s\t%s\t%s\t%s\n" "office_slides_*" "Microsoft PowerPoint" "all-movable-windows" "required document windows; layout adapts to count"
    printf "%s\t%s\t%s\t%s\n" "office_slides_*" "ChatGPT" "optional-helper" "single helper window when present"

    printf "%s\t%s\t%s\t%s\n" "gtd_support_*" "Dia" "all-movable-windows" "movable non-native-fullscreen Dia windows"
    printf "%s\t%s\t%s\t%s\n" "gtd_review_*" "Finder" "all-movable-windows" "snapshot-first; reconciled from final window snapshot"
    printf "%s\t%s\t%s\t%s\n" "gtd_review_*" "Preview" "all-movable-windows;fallback-space-owner" "movable windows; non-movable Preview can own fallback space"
    printf "%s\t%s\t%s\t%s\n" "gtd_review_*" "Notes" "all-movable-windows;fallback-space-owner" "movable windows; non-movable Notes can own fallback space"
    printf "%s\t%s\t%s\t%s\n" "gtd_review_*" "ChatGPT" "optional-helper" "snapshot-first helper; capture only if existing window misses target"
    printf "%s\t%s\t%s\t%s\n" "gtd_mail_*" "Thunderbird" "single-window;fallback-space-owner" "required primary; current space can become mail workspace"
    printf "%s\t%s\t%s\t%s\n" "gtd_mail_*" "Microsoft Outlook" "optional-helper" "single helper window when present"
    printf "%s\t%s\t%s\t%s\n" "gtd_meeting_*" "Zoom" "all-movable-windows;fallback-space-owner" "meeting/video/share windows; current Zoom space fallback"
    printf "%s\t%s\t%s\t%s\n" "gtd_meeting_*" "Microsoft Teams/MSTeams" "all-movable-windows;fallback-space-owner" "meeting/video/call/share windows; non-movable companion space fallback"
    printf "%s\t%s\t%s\t%s\n" "gtd_ai" "ChatGPT" "single-window" "first movable app-key window; opened when missing"
    printf "%s\t%s\t%s\t%s\n" "gtd_ai" "Obsidian" "single-window" "first movable app-key window; opened when missing"
    printf "%s\t%s\t%s\t%s\n" "gtd_ai" "Notes" "single-window" "first movable app-key window; opened when missing"
    printf "%s\t%s\t%s\t%s\n" "gtd_chat" "WeChat" "single-window" "optional chat app; first movable app-key window"
    printf "%s\t%s\t%s\t%s\n" "gtd_chat" "Keybase" "single-window" "optional chat app; first movable app-key window"
    printf "%s\t%s\t%s\t%s\n" "gtd_chat" "DingTalk" "single-window;fallback-space-owner" "first app-key window; current space fallback when non-movable"
    printf "%s\t%s\t%s\t%s\n" "gtd_chat" "Messages" "single-window" "optional chat app; first movable app-key window"
    printf "%s\t%s\t%s\t%s\n" "gtd_chat" "WhatsApp" "optional-helper" "single window; move failures tolerated"
    printf "%s\t%s\t%s\t%s\n" "gtd_calendar" "Calendar" "single-window;fallback-space-owner" "first app-key window; current space fallback when non-movable"
    printf "%s\t%s\t%s\t%s\n" "gtd_calendar" "Reminders" "single-window" "first movable app-key window"
end

function workspace_print_ownership_policy --description "Print the static workspace app ownership policy table"
    printf "%-24s %-24s %-44s %s\n" "workspace" "app" "policy" "notes"

    workspace_ownership_policy_rows | while read -l row
        set -l parts (string split \t -- "$row")
        printf "%-24s %-24s %-44s %s\n" $parts[1] $parts[2] $parts[3] $parts[4]
    end
end

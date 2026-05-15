function gtd_mode_status --description "Show GTD spaces grouped by mode"
    workspace_mode_status_section "GTD SOLO SPACES" '^gtd_.*_solo$'

    echo
    workspace_mode_status_section "GTD WIDE SPACES" '^gtd_.*_wide$'

    echo
    workspace_mode_status_section "GTD TALL SPACES" '^gtd_.*_tall$'

    echo
    workspace_mode_status_section "GTD INTERNAL SPACES" '^(gtd_chat|gtd_calendar)$'
end

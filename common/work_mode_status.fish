function work_mode_status
    echo "===== GTD MODE STATUS ====="
    workspace_mode_status_section "GTD SOLO SPACES" '^gtd_.*_solo$'
    echo
    workspace_mode_status_section "GTD WIDE SPACES" '^gtd_.*_wide$'
    echo
    workspace_mode_status_section "GTD TALL SPACES" '^gtd_.*_tall$'
    echo
    workspace_mode_status_section "GTD INTERNAL SPACES" '^(gtd_chat|gtd_calendar)$'

    echo
    echo "===== CODING MODE STATUS ====="
    workspace_mode_status_section "CODING SOLO SPACES" '^coding_.*_solo$'
    echo
    workspace_mode_status_section "CODING WIDE SPACES" '^coding_.*_wide$'
    echo
    workspace_mode_status_section "CODING TALL SPACES" '^coding_.*_tall$'
    echo
    workspace_mode_status_section "CODING INTERNAL SPACES" '^coding_control$'

    echo
    echo "===== OFFICE MODE STATUS ====="
    workspace_mode_status_section "OFFICE SOLO SPACES" '^office_.*_solo$'
    echo
    workspace_mode_status_section "OFFICE WIDE SPACES" '^office_.*_wide$'
    echo
    workspace_mode_status_section "OFFICE TALL SPACES" '^office_.*_tall$'

    echo
    echo "===== RESEARCH MODE STATUS ====="
    workspace_mode_status_section "RESEARCH SOLO SPACES" '^research(_.*)?_solo$'
    echo
    workspace_mode_status_section "RESEARCH WIDE SPACES" '^research(_.*)?_wide$'
    echo
    workspace_mode_status_section "RESEARCH TALL SPACES" '^research(_.*)?_tall$'
end

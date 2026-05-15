function coding_mode_status --description "Show coding spaces grouped by mode"
    workspace_mode_status_section "CODING SOLO SPACES" '^coding_.*_solo$'

    echo
    workspace_mode_status_section "CODING WIDE SPACES" '^coding_.*_wide$'

    echo
    workspace_mode_status_section "CODING TALL SPACES" '^coding_.*_tall$'

    echo
    workspace_mode_status_section "CODING INTERNAL SPACES" '^coding_control$'
end

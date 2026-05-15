function office_mode_status --description "Show office spaces grouped by mode"
    workspace_mode_status_section "OFFICE SOLO SPACES" '^office_.*_solo$'

    echo
    workspace_mode_status_section "OFFICE WIDE SPACES" '^office_.*_wide$'

    echo
    workspace_mode_status_section "OFFICE TALL SPACES" '^office_.*_tall$'
end

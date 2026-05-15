function research_mode_status --description "Show research spaces grouped by mode"
    workspace_mode_status_section "RESEARCH SOLO SPACES" '^research(_.*)?_solo$'

    echo
    workspace_mode_status_section "RESEARCH WIDE SPACES" '^research(_.*)?_wide$'

    echo
    workspace_mode_status_section "RESEARCH TALL SPACES" '^research(_.*)?_tall$'
end

function work_check --description "Run workspace reload and mode-status checks"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Run a lightweight check for the workspace system after modifying
    #   workspace functions.
    #
    # Behavior:
    #   1. Reload all workspace modules
    #   2. Print mode-status outputs for GTD, coding, office, and research
    # -------------------------------------------------------------------------

    echo "===== RELOAD ====="
    gtd_reload
    coding_reload
    office_reload
    research_reload

    echo
    echo "===== GTD MODE STATUS ====="
    gtd_mode_status

    echo
    echo "===== CODING MODE STATUS ====="
    coding_mode_status

    echo
    echo "===== OFFICE MODE STATUS ====="
    office_mode_status

    echo
    echo "===== RESEARCH MODE STATUS ====="
    research_mode_status
end
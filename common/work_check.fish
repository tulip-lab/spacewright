function work_check --description "Run workspace reload and mode-status checks"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Run a lightweight check for the workspace system after modifying
    #   workspace functions.
    #
    # Behavior:
    #   1. Reload all workspace modules
    #   2. Print read-only diagnostics
    #   3. Print mode-status outputs for GTD, coding, office, and research
    # -------------------------------------------------------------------------

    echo "===== RELOAD ====="
    gtd_reload
    coding_reload
    office_reload
    research_reload

    echo
    echo "===== WORKSPACE DIAGNOSTICS ====="
    work_diagnostics

    echo
    work_mode_status
end

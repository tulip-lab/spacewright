function gtd_tall_all --description "Arrange all GTD tall workspaces including internal fixed workspaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter the complete GTD tall mode by arranging:
    #     - all GTD tall-mode workspaces
    #     - internal fixed GTD workspaces
    #
    # Behavior:
    #   - Delegate tall-mode workspace arrangement to `gtd_tall`
    #   - Keep internal workspaces (`gtd_chat`, `gtd_calendar`) available
    #
    # Notes:
    #   `gtd_tall` already performs the required opposite-mode cleanup, so this
    #   wrapper does not repeat cleanup again.
    # -------------------------------------------------------------------------

    set -l failed 0

    workspace_run_step "GTD tall mode" gtd_tall
    or set failed 1

    workspace_run_step "GTD chat internal" gtd_chat
    or set failed 1

    workspace_run_step "GTD calendar internal" gtd_calendar
    or set failed 1

    return $failed
end

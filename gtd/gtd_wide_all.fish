function gtd_wide_all --description "Arrange all GTD wide workspaces including internal fixed workspaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter the complete GTD wide mode by arranging:
    #     - all GTD wide-mode workspaces
    #     - internal fixed GTD workspaces
    #
    # Behavior:
    #   - Delegate wide-mode workspace arrangement to `gtd_wide`
    #   - Keep internal workspaces (`gtd_chat`, `gtd_calendar`) available
    #
    # Notes:
    #   `gtd_wide` already performs the required opposite-mode cleanup, so this
    #   wrapper does not repeat cleanup again.
    # -------------------------------------------------------------------------

    set -l failed 0

    workspace_run_step "GTD wide mode" gtd_wide
    or set failed 1

    workspace_run_step "GTD chat internal" gtd_chat
    or set failed 1

    workspace_run_step "GTD calendar internal" gtd_calendar
    or set failed 1

    return $failed
end

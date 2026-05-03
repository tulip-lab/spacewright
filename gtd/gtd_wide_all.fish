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

    gtd_wide
    gtd_chat
    gtd_calendar
end
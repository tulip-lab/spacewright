function coding_wide_all --description "Arrange all coding wide workspaces including internal fixed workspaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter the complete coding wide mode by arranging:
    #     - all coding wide-mode workspaces
    #     - internal fixed coding workspaces
    #
    # Notes:
    #   `coding_wide` already performs the required opposite-mode cleanup, so
    #   this wrapper does not repeat cleanup again.
    # -------------------------------------------------------------------------

    coding_wide
    coding_control
end
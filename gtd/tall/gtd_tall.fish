function gtd_tall --description "Arrange all GTD tall workspaces and clean opposite-mode spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter GTD tall mode by arranging all tall-mode GTD workspaces.
    #
    # Behavior:
    #   - Clean empty GTD wide spaces before switching
    #   - Arrange all GTD tall workspaces
    #   - Clean empty GTD wide spaces again after switching
    #
    # Managed tall workspaces:
    #   - gtd_mail_tall
    #   - gtd_meeting_tall
    #   - gtd_support_tall
    #   - gtd_review_tall
    # -------------------------------------------------------------------------

    gtd_cleanup_wide_spaces

    gtd_support_tall
    gtd_review_tall

    gtd_mail_tall
    gtd_meeting_tall

    gtd_cleanup_wide_spaces
end
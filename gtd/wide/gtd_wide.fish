function gtd_wide --description "Arrange all GTD wide workspaces and clean opposite-mode spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter GTD wide mode by arranging all wide-mode GTD workspaces.
    #
    # Behavior:
    #   - Clean empty GTD tall spaces before switching
    #   - Arrange all GTD wide workspaces
    #   - Clean empty GTD tall spaces again after switching
    #
    # Managed wide workspaces:
    #   - gtd_mail_wide
    #   - gtd_meeting_wide
    #   - gtd_support_wide
    #   - gtd_review_wide
    # -------------------------------------------------------------------------

    gtd_cleanup_tall_spaces

    gtd_mail_wide
    gtd_meeting_wide
    gtd_support_wide
    gtd_review_wide

    gtd_cleanup_tall_spaces
end
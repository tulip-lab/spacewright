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
    gtd_cleanup_solo_spaces

    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    gtd_support_wide
    gtd_review_wide
    
    gtd_mail_wide
    gtd_meeting_wide

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces
end

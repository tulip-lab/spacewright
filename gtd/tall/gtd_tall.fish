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

    workspace_cleanup_mode_spaces gtd wide
    workspace_cleanup_mode_spaces gtd solo
    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    gtd_support_tall
    gtd_review_tall

    gtd_mail_tall
    gtd_meeting_tall

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    workspace_cleanup_mode_spaces gtd wide
    workspace_cleanup_mode_spaces gtd solo
end

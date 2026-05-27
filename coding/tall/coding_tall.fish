function coding_tall --description "Arrange all coding tall workspaces and clean opposite-mode spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter coding tall mode by arranging all coding tall workspaces.
    #
    # Behavior:
    #   - Clean empty coding wide spaces before switching
    #   - Arrange all coding tall workspaces
    #   - Clean empty coding wide spaces again after switching
    #
    # Managed tall workspaces:
    #   - coding_editor_tall
    # -------------------------------------------------------------------------

    workspace_cleanup_mode_spaces coding wide
    workspace_cleanup_mode_spaces coding solo
    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    coding_editor_tall

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    workspace_cleanup_mode_spaces coding wide
    workspace_cleanup_mode_spaces coding solo
end

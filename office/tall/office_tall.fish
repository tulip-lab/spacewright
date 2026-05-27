function office_tall --description "Arrange all office tall workspaces and clean opposite-mode spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter office tall mode by arranging all office tall workspaces.
    #
    # Behavior:
    #   - Clean empty office wide spaces before switching
    #   - Arrange all office tall workspaces
    #   - Clean empty office wide spaces again after switching
    #
    # Managed tall workspaces:
    #   - office_writing_tall
    #   - office_slides_tall
    # -------------------------------------------------------------------------

    workspace_cleanup_mode_spaces office wide
    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    office_writing_tall
    office_slides_tall

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    workspace_cleanup_mode_spaces office wide
end

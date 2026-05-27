function office_wide --description "Arrange all office wide workspaces and clean opposite-mode spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter office wide mode by arranging all office wide workspaces.
    #
    # Behavior:
    #   - Clean empty office tall spaces before switching
    #   - Arrange all office wide workspaces
    #   - Clean empty office tall spaces again after switching
    #
    # Managed wide workspaces:
    #   - office_writing_wide
    #   - office_slides_wide
    # -------------------------------------------------------------------------

    workspace_cleanup_mode_spaces office tall
    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    office_writing_wide
    office_slides_wide

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    workspace_cleanup_mode_spaces office tall
end

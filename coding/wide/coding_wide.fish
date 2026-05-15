function coding_wide --description "Arrange all coding wide workspaces and clean opposite-mode spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter coding wide mode by arranging all coding wide workspaces.
    #
    # Behavior:
    #   - Clean empty coding tall spaces before switching
    #   - Arrange all coding wide workspaces
    #   - Clean empty coding tall spaces again after switching
    #
    # Managed wide workspaces:
    #   - coding_editor_wide
    # -------------------------------------------------------------------------

    coding_cleanup_tall_spaces
    coding_cleanup_solo_spaces

    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    coding_editor_wide

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    coding_cleanup_tall_spaces
    coding_cleanup_solo_spaces
end

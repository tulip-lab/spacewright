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

    coding_editor_wide

    coding_cleanup_tall_spaces
end
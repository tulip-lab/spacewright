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

    coding_cleanup_wide_spaces

    coding_editor_tall

    coding_cleanup_wide_spaces
end
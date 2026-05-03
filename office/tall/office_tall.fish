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

    office_cleanup_wide_spaces

    office_writing_tall
    office_slides_tall

    office_cleanup_wide_spaces
end
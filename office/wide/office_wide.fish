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

    office_cleanup_tall_spaces

    office_writing_wide
    office_slides_wide

    office_cleanup_tall_spaces
end
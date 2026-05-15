function office_reload --description "Reload all office workspace functions and helpers"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full office workspace function set after editing files.
    #
    # Reload order:
    #   1. Common workspace helpers
    #   2. Office cleanup helpers
    #   3. Concrete office workspace functions
    #   4. Status / inspection helpers
    # -------------------------------------------------------------------------

    # 1. Common workspace helpers
    if test "$WORKSPACE_SKIP_COMMON_RELOAD" != "1"
        source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
        source_workspace_common
    end

    # 2. Office cleanup helpers
    source ~/.config/fish/functions/workspace/office/office_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/office/office_cleanup_tall_spaces.fish
    source ~/.config/fish/functions/workspace/office/office_cleanup_solo_spaces.fish

    # 3. Concrete office workspace functions
    source ~/.config/fish/functions/workspace/office/wide/office_writing_wide.fish
    source ~/.config/fish/functions/workspace/office/wide/office_slides_wide.fish
    source ~/.config/fish/functions/workspace/office/wide/office_wide.fish

    source ~/.config/fish/functions/workspace/office/tall/office_writing_tall.fish
    source ~/.config/fish/functions/workspace/office/tall/office_slides_tall.fish
    source ~/.config/fish/functions/workspace/office/tall/office_tall.fish

    # 4. Status / inspection helpers
    source ~/.config/fish/functions/workspace/office/office_status.fish
    source ~/.config/fish/functions/workspace/office/office_mode_status.fish
end

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
    source ~/.config/fish/functions/workspace/common/focus_display_if_needed.fish
    source ~/.config/fish/functions/workspace/common/focus_space_if_needed.fish

    source ~/.config/fish/functions/workspace/common/resolve_target_display.fish
    source ~/.config/fish/functions/workspace/common/find_or_create_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/prepare_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/cleanup_unlabeled_empty_spaces.fish
    source ~/.config/fish/functions/workspace/common/ws_focus_display.fish
    source ~/.config/fish/functions/workspace/common/ws_focus_space.fish

    source ~/.config/fish/functions/workspace/common/set_internal_display_uuid.fish
    source ~/.config/fish/functions/workspace/common/get_internal_display_uuid.fish
    source ~/.config/fish/functions/workspace/common/resolve_internal_display.fish
    source ~/.config/fish/functions/workspace/common/resolve_external_display.fish

    # 2. Office cleanup helpers
    source ~/.config/fish/functions/workspace/office/office_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/office/office_cleanup_tall_spaces.fish

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
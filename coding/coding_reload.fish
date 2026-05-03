function coding_reload --description "Reload all coding workspace functions and helpers"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full coding workspace function set after editing files.
    #
    # Reload order:
    #   1. Common workspace helpers
    #   2. Coding cleanup helpers
    #   3. Concrete coding workspace functions
    #   4. Aggregate entry functions
    #   5. Status / inspection helpers
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

    # 2. Coding cleanup helpers
    source ~/.config/fish/functions/workspace/coding/coding_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/coding/coding_cleanup_tall_spaces.fish

    # 3. Concrete coding workspace functions
    source ~/.config/fish/functions/workspace/coding/wide/coding_editor_wide.fish
    source ~/.config/fish/functions/workspace/coding/wide/coding_wide.fish
    source ~/.config/fish/functions/workspace/coding/tall/coding_editor_tall.fish
    source ~/.config/fish/functions/workspace/coding/tall/coding_tall.fish
    source ~/.config/fish/functions/workspace/coding/internal/coding_control.fish

    # 4. Aggregate entry functions
    source ~/.config/fish/functions/workspace/coding/coding_wide_all.fish
    source ~/.config/fish/functions/workspace/coding/coding_tall_all.fish

    # 5. Status / inspection helpers
    source ~/.config/fish/functions/workspace/coding/coding_status.fish
    source ~/.config/fish/functions/workspace/coding/coding_mode_status.fish
end
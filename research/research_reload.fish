function research_reload --description "Reload all research workspace functions and helpers"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full research workspace function set after editing files.
    #
    # Reload order:
    #   1. Common workspace helpers
    #   2. Research cleanup helpers
    #   3. Concrete research workspace functions
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

    # 2. Research cleanup helpers
    source ~/.config/fish/functions/workspace/research/research_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/research/research_cleanup_tall_spaces.fish

    # 3. Concrete research workspace functions
    source ~/.config/fish/functions/workspace/research/wide/research_wide.fish
    source ~/.config/fish/functions/workspace/research/tall/research_tall.fish

    # 4. Status / inspection helpers
    source ~/.config/fish/functions/workspace/research/research_status.fish
    source ~/.config/fish/functions/workspace/research/research_mode_status.fish
end
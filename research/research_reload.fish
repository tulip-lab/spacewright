function research_reload
    source ~/.config/fish/functions/workspace/common/focus_display_if_needed.fish
    source ~/.config/fish/functions/workspace/common/focus_space_if_needed.fish

    source ~/.config/fish/functions/workspace/research/wide/research_wide.fish
    source ~/.config/fish/functions/workspace/research/tall/research_tall.fish
    source ~/.config/fish/functions/workspace/research/research_status.fish
    source ~/.config/fish/functions/workspace/research/research_mode_status.fish
    source ~/.config/fish/functions/workspace/research/research_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/research/research_cleanup_tall_spaces.fish
end
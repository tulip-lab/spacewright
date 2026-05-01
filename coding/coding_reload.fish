function coding_reload
    source ~/.config/fish/functions/workspace/common/focus_display_if_needed.fish
    source ~/.config/fish/functions/workspace/common/focus_space_if_needed.fish

    source ~/.config/fish/functions/workspace/coding/wide/coding_editor_wide.fish
    source ~/.config/fish/functions/workspace/coding/wide/coding_wide.fish
    source ~/.config/fish/functions/workspace/coding/tall/coding_editor_tall.fish
    source ~/.config/fish/functions/workspace/coding/tall/coding_tall.fish
    source ~/.config/fish/functions/workspace/coding/internal/coding_control.fish
    source ~/.config/fish/functions/workspace/coding/coding_wide_all.fish
    source ~/.config/fish/functions/workspace/coding/coding_tall_all.fish
    source ~/.config/fish/functions/workspace/coding/coding_status.fish
    source ~/.config/fish/functions/workspace/coding/coding_mode_status.fish
    source ~/.config/fish/functions/workspace/coding/coding_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/coding/coding_cleanup_tall_spaces.fish
end
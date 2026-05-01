function office_reload
    source ~/.config/fish/functions/workspace/common/focus_display_if_needed.fish
    source ~/.config/fish/functions/workspace/common/focus_space_if_needed.fish

    source ~/.config/fish/functions/workspace/office/wide/office_writing_wide.fish
    source ~/.config/fish/functions/workspace/office/wide/office_slides_wide.fish
    source ~/.config/fish/functions/workspace/office/wide/office_wide.fish
    source ~/.config/fish/functions/workspace/office/tall/office_writing_tall.fish
    source ~/.config/fish/functions/workspace/office/tall/office_slides_tall.fish
    source ~/.config/fish/functions/workspace/office/tall/office_tall.fish
    source ~/.config/fish/functions/workspace/office/office_status.fish
    source ~/.config/fish/functions/workspace/office/office_mode_status.fish
    source ~/.config/fish/functions/workspace/office/office_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/office/office_cleanup_tall_spaces.fish
end
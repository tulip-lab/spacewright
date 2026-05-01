function work_reload
    source ~/.config/fish/functions/workspace/common/focus_display_if_needed.fish
    source ~/.config/fish/functions/workspace/common/focus_space_if_needed.fish

    source ~/.config/fish/functions/workspace/display/display_reload.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_reload.fish
    source ~/.config/fish/functions/workspace/coding/coding_reload.fish
    source ~/.config/fish/functions/workspace/office/office_reload.fish
    source ~/.config/fish/functions/workspace/research/research_reload.fish
    source ~/.config/fish/functions/workspace/common/work_status.fish
    source ~/.config/fish/functions/workspace/common/work_mode_status.fish
    source ~/.config/fish/functions/workspace/common/work_wide.fish
    source ~/.config/fish/functions/workspace/common/work_tall.fish

    display_reload
    gtd_reload
    coding_reload
    office_reload
    research_reload
end
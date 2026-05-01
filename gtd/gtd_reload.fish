function gtd_reload
    source ~/.config/fish/functions/workspace/common/focus_display_if_needed.fish
    source ~/.config/fish/functions/workspace/common/focus_space_if_needed.fish

    source ~/.config/fish/functions/workspace/gtd/wide/gtd_mail_wide.fish
    source ~/.config/fish/functions/workspace/gtd/wide/gtd_meeting_wide.fish
    source ~/.config/fish/functions/workspace/gtd/wide/gtd_support_wide.fish
    source ~/.config/fish/functions/workspace/gtd/wide/gtd_review_wide.fish
    source ~/.config/fish/functions/workspace/gtd/wide/gtd_wide.fish

    source ~/.config/fish/functions/workspace/gtd/tall/gtd_mail_tall.fish
    source ~/.config/fish/functions/workspace/gtd/tall/gtd_meeting_tall.fish
    source ~/.config/fish/functions/workspace/gtd/tall/gtd_support_tall.fish
    source ~/.config/fish/functions/workspace/gtd/tall/gtd_review_tall.fish
    source ~/.config/fish/functions/workspace/gtd/tall/gtd_tall.fish

    source ~/.config/fish/functions/workspace/gtd/internal/gtd_chat.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_calendar.fish

    source ~/.config/fish/functions/workspace/gtd/gtd_wide_all.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_tall_all.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_status.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_labels.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_apps.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_reset_labels.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_mode_status.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_cleanup_tall_spaces.fish
end
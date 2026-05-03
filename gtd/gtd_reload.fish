function gtd_reload --description "Reload all GTD workspace functions and helpers"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full GTD workspace function set after editing files.
    #
    # Reload order:
    #   1. Common workspace helpers
    #   2. GTD cleanup / metadata helpers
    #   3. GTD concrete workspace functions
    #   4. GTD aggregate entry functions
    #   5. GTD status / inspection helpers
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

    # 2. GTD cleanup / metadata helpers
    source ~/.config/fish/functions/workspace/gtd/gtd_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_cleanup_tall_spaces.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_reset_labels.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_labels.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_apps.fish

    # 3. GTD concrete workspace functions
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_chat.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_calendar.fish

    source ~/.config/fish/functions/workspace/gtd/tall/gtd_mail_tall.fish
    source ~/.config/fish/functions/workspace/gtd/tall/gtd_meeting_tall.fish
    source ~/.config/fish/functions/workspace/gtd/tall/gtd_support_tall.fish
    source ~/.config/fish/functions/workspace/gtd/tall/gtd_review_tall.fish
    source ~/.config/fish/functions/workspace/gtd/tall/gtd_tall.fish

    source ~/.config/fish/functions/workspace/gtd/wide/gtd_mail_wide.fish
    source ~/.config/fish/functions/workspace/gtd/wide/gtd_meeting_wide.fish
    source ~/.config/fish/functions/workspace/gtd/wide/gtd_support_wide.fish
    source ~/.config/fish/functions/workspace/gtd/wide/gtd_review_wide.fish
    source ~/.config/fish/functions/workspace/gtd/wide/gtd_wide.fish

    # 4. GTD aggregate entry functions
    source ~/.config/fish/functions/workspace/gtd/gtd_tall_all.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_wide_all.fish

    # 5. GTD status / inspection helpers
    source ~/.config/fish/functions/workspace/gtd/gtd_mode_status.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_status.fish
end
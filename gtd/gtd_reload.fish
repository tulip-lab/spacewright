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
    if test "$WORKSPACE_SKIP_COMMON_RELOAD" != "1"
        source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
        source_workspace_common
    end

    # 2. GTD cleanup / metadata helpers
    source ~/.config/fish/functions/workspace/gtd/gtd_cleanup_wide_spaces.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_cleanup_tall_spaces.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_cleanup_solo_spaces.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_reset_labels.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_labels.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_apps.fish

    # 3. GTD concrete workspace functions
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_find_outlook_window.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_reopen_outlook.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_chat.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_calendar.fish

    source ~/.config/fish/functions/workspace/gtd/solo/gtd_mail_solo.fish
    source ~/.config/fish/functions/workspace/gtd/solo/gtd_meeting_solo.fish
    source ~/.config/fish/functions/workspace/gtd/solo/gtd_review_solo.fish
    source ~/.config/fish/functions/workspace/gtd/solo/gtd_support_solo.fish

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
    source ~/.config/fish/functions/workspace/gtd/gtd_solo_all.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_tall_all.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_wide_all.fish

    # 5. GTD status / inspection helpers
    source ~/.config/fish/functions/workspace/gtd/gtd_mode_status.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_status.fish
end

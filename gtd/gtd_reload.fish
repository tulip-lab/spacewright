function gtd_reload --description "Reload all GTD workspace functions and helpers"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full GTD workspace function set after editing files.
    #
    # Reload order:
    #   1. Common workspace helpers
    #   2. GTD metadata helpers
    #   3. GTD internal helpers and entry functions
    #   4. GTD status / inspection helpers
    # -------------------------------------------------------------------------

    # 1. Common workspace helpers
    if test "$WORKSPACE_SKIP_COMMON_RELOAD" != "1"
        source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
        source_workspace_common
    end

    # 2. GTD metadata helpers
    source ~/.config/fish/functions/workspace/gtd/gtd_apps.fish

    # 3. GTD internal helpers and entry functions
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_find_outlook_window.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_find_meeting_window.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_reopen_outlook.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_apply_meeting_space.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_apply_support_space.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_apply_review_space.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_support_find_dia_windows.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_support_layout_dia_windows.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_chat.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_calendar.fish

    source ~/.config/fish/functions/workspace/gtd/gtd_entries.fish

    # 4. GTD status / inspection helpers
    source ~/.config/fish/functions/workspace/gtd/gtd_status.fish
end

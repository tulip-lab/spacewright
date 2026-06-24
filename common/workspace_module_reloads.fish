function workspace_source_common_if_needed --description "Source common workspace helpers unless a parent reload already did so"
    if test "$WORKSPACE_SKIP_COMMON_RELOAD" != "1"
        source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
        source_workspace_common
    end
end

function coding_reload --description "Reload coding workspace functions and helpers"
    workspace_source_common_if_needed
    source ~/.config/fish/functions/workspace/coding/coding_entries.fish
    source ~/.config/fish/functions/workspace/coding/internal/coding_control.fish
end

function gtd_reload --description "Reload GTD workspace functions and helpers"
    workspace_source_common_if_needed

    source ~/.config/fish/functions/workspace/gtd/gtd_apps.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_find_outlook_window.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_find_meeting_window.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_reopen_outlook.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_apply_meeting_space.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_apply_support_space.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_apply_review_space.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_apply_ai_space.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_support_find_dia_windows.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_support_layout_dia_windows.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_chat.fish
    source ~/.config/fish/functions/workspace/gtd/internal/gtd_calendar.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_entries.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_status.fish
end

function office_reload --description "Reload office workspace functions and helpers"
    workspace_source_common_if_needed
    source ~/.config/fish/functions/workspace/office/office_entries.fish
end

function research_reload --description "Reload research workspace functions and helpers"
    workspace_source_common_if_needed
    source ~/.config/fish/functions/workspace/research/research_entries.fish
end

function work_reload --description "Reload all workspace display/common/module functions"
    # -------------------------------------------------------------------------
    # Common helpers
    # -------------------------------------------------------------------------
    source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
    source_workspace_common

    # -------------------------------------------------------------------------
    # Display layer
    # -------------------------------------------------------------------------
    source ~/.config/fish/functions/workspace/display/display_reload.fish

    # -------------------------------------------------------------------------
    # Module reloaders
    # -------------------------------------------------------------------------
    source ~/.config/fish/functions/workspace/gtd/gtd_reload.fish
    source ~/.config/fish/functions/workspace/coding/coding_reload.fish
    source ~/.config/fish/functions/workspace/office/office_reload.fish
    source ~/.config/fish/functions/workspace/research/research_reload.fish

    # -------------------------------------------------------------------------
    # Top-level work entry points
    # -------------------------------------------------------------------------
    source ~/.config/fish/functions/workspace/common/work_status.fish
    source ~/.config/fish/functions/workspace/common/work_diagnostics.fish
    source ~/.config/fish/functions/workspace/common/work_bad_windows.fish
    source ~/.config/fish/functions/workspace/common/work_clear_bad_windows.fish
    source ~/.config/fish/functions/workspace/common/work_recover_light.fish
    source ~/.config/fish/functions/workspace/common/work_command_check.fish
    source ~/.config/fish/functions/workspace/common/work_inventory.fish
    source ~/.config/fish/functions/workspace/common/work_doctor.fish
    source ~/.config/fish/functions/workspace/common/work_smoke.fish
    source ~/.config/fish/functions/workspace/common/work_mode_status.fish
    source ~/.config/fish/functions/workspace/common/work_entries.fish
    source ~/.config/fish/functions/workspace/common/work_check.fish

    # -------------------------------------------------------------------------
    # Reload nested modules
    # -------------------------------------------------------------------------
    set -l had_skip_common_reload 0
    set -l previous_skip_common_reload

    if set -q WORKSPACE_SKIP_COMMON_RELOAD
        set had_skip_common_reload 1
        set previous_skip_common_reload $WORKSPACE_SKIP_COMMON_RELOAD
    end

    set -g WORKSPACE_SKIP_COMMON_RELOAD 1

    display_reload
    gtd_reload
    coding_reload
    office_reload
    research_reload

    if test "$had_skip_common_reload" -eq 1
        set -g WORKSPACE_SKIP_COMMON_RELOAD $previous_skip_common_reload
    else
        set -e WORKSPACE_SKIP_COMMON_RELOAD
    end
end

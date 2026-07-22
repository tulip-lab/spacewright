function work_reload --description "Reload all workspace display/common/module functions"
    # -------------------------------------------------------------------------
    # Common helpers
    # -------------------------------------------------------------------------
    source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
    source_workspace_common

    # -------------------------------------------------------------------------
    # Display layer
    # -------------------------------------------------------------------------
    source ~/.config/fish/functions/workspace/display/display_entries.fish

    # -------------------------------------------------------------------------
    # Module reloaders
    # -------------------------------------------------------------------------
    source ~/.config/fish/functions/workspace/common/workspace_module_reloads.fish

    # -------------------------------------------------------------------------
    # Top-level work entry points
    # -------------------------------------------------------------------------
    source ~/.config/fish/functions/workspace/common/workspace_status_helpers.fish
    source ~/.config/fish/functions/workspace/common/work_diagnostics.fish
    source ~/.config/fish/functions/workspace/common/work_bad_windows.fish
    source ~/.config/fish/functions/workspace/common/work_clear_bad_windows.fish
    source ~/.config/fish/functions/workspace/common/work_command_check.fish
    source ~/.config/fish/functions/workspace/common/work_inventory.fish
    source ~/.config/fish/functions/workspace/common/work_audit.fish
    source ~/.config/fish/functions/workspace/common/work_doctor.fish
    source ~/.config/fish/functions/workspace/common/work_smoke.fish
    source ~/.config/fish/functions/workspace/common/work_smoke_observability.fish
    source ~/.config/fish/functions/workspace/common/work_entries.fish

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

if not set -q SPACEWRIGHT_ROOT; or test -z "$SPACEWRIGHT_ROOT"
    set -l work_reload_file (path resolve (status filename))
    source (path dirname $work_reload_file)/spacewright_paths.fish
end

function work_reload --description "Reload all workspace display/common/module functions"
    # -------------------------------------------------------------------------
    # Common helpers
    # -------------------------------------------------------------------------
    source "$SPACEWRIGHT_ROOT/common/source_workspace_common.fish"
    source_workspace_common

    # -------------------------------------------------------------------------
    # Display layer
    # -------------------------------------------------------------------------
    source "$SPACEWRIGHT_ROOT/display/display_entries.fish"

    # -------------------------------------------------------------------------
    # Module reloaders
    # -------------------------------------------------------------------------
    source "$SPACEWRIGHT_ROOT/common/workspace_module_reloads.fish"

    # -------------------------------------------------------------------------
    # Top-level work entry points
    # -------------------------------------------------------------------------
    source "$SPACEWRIGHT_ROOT/common/workspace_status_helpers.fish"
    source "$SPACEWRIGHT_ROOT/common/work_diagnostics.fish"
    source "$SPACEWRIGHT_ROOT/common/work_bad_windows.fish"
    source "$SPACEWRIGHT_ROOT/common/work_clear_bad_windows.fish"
    source "$SPACEWRIGHT_ROOT/common/work_command_check.fish"
    source "$SPACEWRIGHT_ROOT/common/work_inventory.fish"
    source "$SPACEWRIGHT_ROOT/common/work_audit.fish"
    source "$SPACEWRIGHT_ROOT/common/yabai_doctor.fish"
    source "$SPACEWRIGHT_ROOT/common/work_doctor.fish"
    source "$SPACEWRIGHT_ROOT/common/work_smoke.fish"
    source "$SPACEWRIGHT_ROOT/common/work_smoke_observability.fish"
    source "$SPACEWRIGHT_ROOT/common/work_smoke_finalization.fish"
    source "$SPACEWRIGHT_ROOT/common/work_entries.fish"

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

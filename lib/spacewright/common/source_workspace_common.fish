if not set -q SPACEWRIGHT_ROOT; or test -z "$SPACEWRIGHT_ROOT"
    set -l source_workspace_common_file (path resolve (status filename))
    source (path dirname $source_workspace_common_file)/spacewright_paths.fish
end

function source_workspace_common --description "Source shared workspace helper functions"
    source "$SPACEWRIGHT_ROOT/common/ws_core.fish"
    source "$SPACEWRIGHT_ROOT/common/spacewright_config.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_manifest.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_app_names.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_observability.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_primary_fixed_separation.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_label_recovery.fish"
    source "$SPACEWRIGHT_ROOT/common/ws_find_windows.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_app_window_selectors.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_native_fullscreen.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_app_window_lifecycle.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_app_space_fallback.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_app_bounds.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_runners.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_order_spaces.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_labeled_space_lifecycle.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_labeled_space_focus.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_space_fallback.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_retarget_contaminated_space.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_apply_primary_helper_space.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_config_runtime.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_ownership_policy.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_sandbox.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_cleanup_spaces.fish"
    source "$SPACEWRIGHT_ROOT/common/workspace_finalize.fish"
    source "$SPACEWRIGHT_ROOT/common/ws_move_windows_to_space.fish"
    source "$SPACEWRIGHT_ROOT/common/ws_window.fish"

    source "$SPACEWRIGHT_ROOT/common/workspace_display_roles.fish"

    source "$SPACEWRIGHT_ROOT/common/workspace_status_helpers.fish"
    source "$SPACEWRIGHT_ROOT/common/work_display_health.fish"

end

function source_workspace_common --description "Source shared workspace helper functions"
    source ~/.config/fish/functions/workspace/common/focus_display_if_needed.fish
    source ~/.config/fish/functions/workspace/common/focus_space_if_needed.fish
    source ~/.config/fish/functions/workspace/common/ws_focus_display.fish
    source ~/.config/fish/functions/workspace/common/ws_focus_space.fish
    source ~/.config/fish/functions/workspace/common/ws_yabai.fish
    source ~/.config/fish/functions/workspace/common/ws_jq.fish
    source ~/.config/fish/functions/workspace/common/ws_query_windows.fish
    source ~/.config/fish/functions/workspace/common/ws_find_window.fish
    source ~/.config/fish/functions/workspace/common/ws_find_windows.fish
    source ~/.config/fish/functions/workspace/common/workspace_select_app_window.fish
    source ~/.config/fish/functions/workspace/common/workspace_refresh_app_window.fish
    source ~/.config/fish/functions/workspace/common/workspace_debug_step.fish
    source ~/.config/fish/functions/workspace/common/workspace_run_step.fish
    source ~/.config/fish/functions/workspace/common/ws_move_app_to_space.fish
    source ~/.config/fish/functions/workspace/common/ws_move_app_pair_to_space.fish
    source ~/.config/fish/functions/workspace/common/ws_move_windows_to_space.fish
    source ~/.config/fish/functions/workspace/common/ws_window.fish

    source ~/.config/fish/functions/workspace/common/set_internal_display_uuid.fish
    source ~/.config/fish/functions/workspace/common/get_internal_display_uuid.fish
    source ~/.config/fish/functions/workspace/common/detect_and_set_internal_display_uuid.fish

    source ~/.config/fish/functions/workspace/common/find_or_create_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/prepare_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/destroy_empty_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/cleanup_labeled_empty_spaces.fish
    source ~/.config/fish/functions/workspace/common/cleanup_unlabeled_empty_spaces.fish
    source ~/.config/fish/functions/workspace/common/workspace_status_snapshot.fish
    source ~/.config/fish/functions/workspace/common/workspace_mode_status_section.fish
    source ~/.config/fish/functions/workspace/common/work_display_health.fish

    source ~/.config/fish/functions/workspace/common/resolve_target_display.fish
    source ~/.config/fish/functions/workspace/common/resolve_internal_display.fish
    source ~/.config/fish/functions/workspace/common/resolve_external_display.fish
end

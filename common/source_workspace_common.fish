function source_workspace_common --description "Source shared workspace helper functions"
    source ~/.config/fish/functions/workspace/common/ws_focus.fish
    source ~/.config/fish/functions/workspace/common/ws_yabai.fish
    source ~/.config/fish/functions/workspace/common/ws_jq.fish
    source ~/.config/fish/functions/workspace/common/ws_query_windows.fish
    source ~/.config/fish/functions/workspace/common/workspace_app_names.fish
    source ~/.config/fish/functions/workspace/common/ws_find_windows.fish
    source ~/.config/fish/functions/workspace/common/workspace_select_app_window.fish
    source ~/.config/fish/functions/workspace/common/workspace_refresh_app_window.fish
    source ~/.config/fish/functions/workspace/common/workspace_find_app_window.fish
    source ~/.config/fish/functions/workspace/common/workspace_capture_app_window.fish
    source ~/.config/fish/functions/workspace/common/workspace_debug_step.fish
    source ~/.config/fish/functions/workspace/common/workspace_runners.fish
    source ~/.config/fish/functions/workspace/common/workspace_retarget_contaminated_space.fish
    source ~/.config/fish/functions/workspace/common/workspace_labeled_space_entry.fish
    source ~/.config/fish/functions/workspace/common/workspace_apply_primary_helper_space.fish
    source ~/.config/fish/functions/workspace/common/workspace_cleanup_spaces.fish
    source ~/.config/fish/functions/workspace/common/ws_move_windows_to_space.fish
    source ~/.config/fish/functions/workspace/common/ws_window.fish

    source ~/.config/fish/functions/workspace/common/workspace_display_roles.fish

    source ~/.config/fish/functions/workspace/common/find_or_create_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/prepare_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/destroy_empty_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/cleanup_labeled_empty_spaces.fish
    source ~/.config/fish/functions/workspace/common/cleanup_unlabeled_empty_spaces.fish
    source ~/.config/fish/functions/workspace/common/workspace_status_snapshot.fish
    source ~/.config/fish/functions/workspace/common/workspace_mode_status_section.fish
    source ~/.config/fish/functions/workspace/common/workspace_print_app_status.fish
    source ~/.config/fish/functions/workspace/common/work_module_status_entries.fish
    source ~/.config/fish/functions/workspace/common/work_display_health.fish

end

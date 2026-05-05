function work_reload --description "Reload all workspace display/common/module functions"
    # -------------------------------------------------------------------------
    # Common helpers
    # -------------------------------------------------------------------------
    source ~/.config/fish/functions/workspace/common/focus_display_if_needed.fish
    source ~/.config/fish/functions/workspace/common/focus_space_if_needed.fish
    source ~/.config/fish/functions/workspace/common/ws_focus_display.fish
    source ~/.config/fish/functions/workspace/common/ws_focus_space.fish

    source ~/.config/fish/functions/workspace/common/set_internal_display_uuid.fish
    source ~/.config/fish/functions/workspace/common/get_internal_display_uuid.fish
    source ~/.config/fish/functions/workspace/common/detect_and_set_internal_display_uuid.fish

    source ~/.config/fish/functions/workspace/common/find_or_create_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/prepare_labeled_space.fish
    source ~/.config/fish/functions/workspace/common/cleanup_unlabeled_empty_spaces.fish

    source ~/.config/fish/functions/workspace/common/resolve_target_display.fish
    source ~/.config/fish/functions/workspace/common/resolve_internal_display.fish
    source ~/.config/fish/functions/workspace/common/resolve_external_display.fish

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
    source ~/.config/fish/functions/workspace/common/work_mode_status.fish
    source ~/.config/fish/functions/workspace/common/work_wide.fish
    source ~/.config/fish/functions/workspace/common/work_tall.fish
    source ~/.config/fish/functions/workspace/common/work_check.fish

    # -------------------------------------------------------------------------
    # Reload nested modules
    # -------------------------------------------------------------------------
    display_reload
    gtd_reload
    coding_reload
    office_reload
    research_reload
end
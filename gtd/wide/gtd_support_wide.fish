function gtd_support_wide --description "Collect Dia onto the wide GTD support workspace and apply the standard support layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_support_wide
    #
    # Purpose:
    #   Move support-related applications to the GTD support workspace in wide
    #   mode and place them into a stable horizontal layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the workspace primary display if no external display is available.
    #
    # Managed apps:
    #   - Dia
    #
    # Window selection rules:
    #   - Dia:
    #       Prefer a non-minimized window whose title is not empty and does not
    #       contain "New Tab".
    #       If none is found, fall back to any non-minimized Dia window.
    #
    # Layout:
    #   - Dia -> full space
    #
    # Implementation notes:
    #   - Before entering GTD support wide mode, empty GTD tall spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 1. Cleanup GTD tall spaces before entering wide mode
    # -------------------------------------------------------------------------
    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces

    set -l label gtd_support_wide

    # -------------------------------------------------------------------------
    # 2. First-pass window capture
    #    Dia must exist before creating the workspace.
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows "gtd_support_wide" initial); or return 1

    set -l dia_windows (printf '%s\n' "$windows_json" | gtd_support_find_dia_windows gtd_support_wide)
    or return 1

    if test (count $dia_windows) -eq 0
        destroy_empty_labeled_space $label

        return 0
    end

    set -l target_display (resolve_workspace_external_display wide)

    # -------------------------------------------------------------------------
    # 3. Prepare target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (workspace_prepare_labeled_space $label $target_display float gtd_cleanup_tall_spaces gtd_cleanup_solo_spaces)
    or return 1

    # -------------------------------------------------------------------------
    # 5. Move captured Dia windows
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $dia_windows

    # -------------------------------------------------------------------------
    # 6. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows "gtd_support_wide" final); or return 1

    set dia_windows (printf '%s\n' "$windows_json_final" | ws_find_windows "Dia" --space $target_space)

    # -------------------------------------------------------------------------
    # 7. Apply final layout
    #    Keep one Dia full-size and split multiple Dia windows by mode.
    # -------------------------------------------------------------------------
    gtd_support_layout_dia_windows wide $dia_windows

    # -------------------------------------------------------------------------
    # 8. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

function gtd_support_tall --description "Collect Dia onto the tall GTD support workspace and apply the standard support layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_support_tall
    #
    # Purpose:
    #   Move support-related applications to the GTD support workspace in tall
    #   mode and place them into a stable vertical layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
    #
    # Managed apps:
    #   - Dia
    #
    # Window selection rules:
    #   - Dia:
    #       Move all non-minimized Dia windows that yabai reports as movable.
    #       If Dia is present but not movable, activate Dia once and retry the
    #       window capture before failing closed with a warning.
    #
    # Layout:
    #   - 1 Dia window  -> bottom half
    #   - 2 Dia windows -> top half / bottom half
    #   - 3 Dia windows -> two on the top half, one on the bottom half
    #   - 4+ Dia windows -> two-column grid, filled top to bottom
    #
    # Implementation notes:
    #   - Before entering GTD support tall mode, empty GTD wide spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 1. Cleanup GTD wide spaces before entering tall mode
    # -------------------------------------------------------------------------
    gtd_cleanup_wide_spaces
    gtd_cleanup_solo_spaces

    set -l label gtd_support_tall

    # -------------------------------------------------------------------------
    # 2. First-pass window capture
    #    Dia must exist before creating the workspace.
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows "gtd_support_tall" initial); or return 1

    set -l dia_windows (printf '%s\n' "$windows_json" | gtd_support_find_dia_windows gtd_support_tall)
    or return 1

    if test (count $dia_windows) -eq 0
        destroy_empty_labeled_space $label

        return 0
    end

    set -l target_display (resolve_external_display)

    # -------------------------------------------------------------------------
    # 3. Find or create target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    # -------------------------------------------------------------------------
    # 4. Normalize target space state
    # -------------------------------------------------------------------------
    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    gtd_cleanup_wide_spaces
    gtd_cleanup_solo_spaces
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 5. Move captured Dia windows
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $dia_windows

    # -------------------------------------------------------------------------
    # 6. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows "gtd_support_tall" final); or return 1

    set dia_windows (printf '%s\n' "$windows_json_final" | ws_find_windows "Dia" --space $target_space)

    # -------------------------------------------------------------------------
    # 7. Apply final layout
    #    Keep one Dia on the bottom half, split two vertically, and use a
    #    2x2-style layout for three or more windows.
    # -------------------------------------------------------------------------
    gtd_support_layout_dia_windows tall $dia_windows

    # -------------------------------------------------------------------------
    # 8. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    gtd_cleanup_wide_spaces
    gtd_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

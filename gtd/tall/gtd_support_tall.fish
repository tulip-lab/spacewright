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
    #       Prefer all non-minimized windows whose title is not empty and does
    #       not contain "New Tab".
    #       If none are found, fall back to all non-minimized Dia windows.
    #
    # Layout:
    #   - 1 Dia window  -> full space
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

    # Dia: prefer non-empty title and not "New Tab"
    set -l dia_windows (echo $windows_json | ws_find_windows "Dia" --nonempty-title --exclude-title "new tab")

    if test (count $dia_windows) -eq 0
        set dia_windows (echo $windows_json | ws_find_windows "Dia")
    end

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

    set dia_windows (echo $windows_json_final | ws_find_windows "Dia" --space $target_space --nonempty-title --exclude-title "new tab")

    if test (count $dia_windows) -eq 0
        set dia_windows (echo $windows_json_final | ws_find_windows "Dia" --space $target_space)
    end

    # -------------------------------------------------------------------------
    # 7. Apply final layout
    #    Keep one Dia full-size, split two vertically, and use a 2x2-style
    #    layout for three or more windows.
    # -------------------------------------------------------------------------
    set -l dia_count (count $dia_windows)

    if test "$dia_count" -eq 1
        ws_window $dia_windows[1] --grid 1:1:0:0:1:1
    else if test "$dia_count" -eq 2
        ws_window $dia_windows[1] --grid 2:1:0:0:1:1
        ws_window $dia_windows[2] --grid 2:1:0:1:1:1
    else if test "$dia_count" -eq 3
        ws_window $dia_windows[1] --grid 2:2:0:0:1:1
        ws_window $dia_windows[2] --grid 2:2:1:0:1:1
        ws_window $dia_windows[3] --grid 2:1:0:1:1:1
    else if test "$dia_count" -ge 4
        set -l rows (math "ceil($dia_count / 2)")
        set -l i 1

        for wid in $dia_windows
            set -l zero_index (math "$i - 1")
            set -l col (math "$zero_index % 2")
            set -l row (math "floor($zero_index / 2)")

            ws_window $wid --grid $rows:2:$col:$row:1:1
            set i (math "$i + 1")
        end
    end

    # -------------------------------------------------------------------------
    # 8. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    gtd_cleanup_wide_spaces
    gtd_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

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
    #   Fall back to the internal display if no external display is available.
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
    set -l windows_json (yabai -m query --windows)

    # Dia: prefer non-empty title and not "New Tab"
    set -l dia (echo $windows_json | ws_find_window "Dia" --nonempty-title --exclude-title "new tab")

    if test -z "$dia"
        set dia (echo $windows_json | ws_find_window "Dia")
    end

    if test -z "$dia"
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
    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 5. Move captured Dia window
    # -------------------------------------------------------------------------
    ws_move_app_to_space $target_space "Dia" $dia

    # -------------------------------------------------------------------------
    # 6. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set dia (echo $windows_json_final | ws_find_window "Dia" --space $target_space --nonempty-title --exclude-title "new tab")

    if test -z "$dia"
        set dia (echo $windows_json_final | ws_find_window "Dia" --space $target_space)
    end

    # -------------------------------------------------------------------------
    # 7. Apply final layout
    #    Keep Dia full-size on the support workspace.
    # -------------------------------------------------------------------------
    if test -n "$dia"
        ws_window $dia --grid 1:1:0:0:1:1
    end

    # -------------------------------------------------------------------------
    # 8. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

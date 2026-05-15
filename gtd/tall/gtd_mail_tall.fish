function gtd_mail_tall --description "Collect Thunderbird onto the tall GTD mail workspace and apply the standard tall mail layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_mail_tall
    #
    # Purpose:
    #   Move Thunderbird to the GTD mail workspace in tall mode and place it
    #   on the lower half of the target display.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
    #
    # Managed app:
    #   - Thunderbird
    #
    # Layout:
    #   - Thunderbird -> lower half, full width
    #
    # Notes:
    #   - Before entering GTD mail tall mode, empty GTD wide spaces are cleaned.
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

    set -l label gtd_mail_tall

    # -------------------------------------------------------------------------
    # 2. Find Thunderbird first; if not found, do not create the workspace
    # -------------------------------------------------------------------------
    set -l windows_json (yabai -m query --windows)

    set -l tb (echo $windows_json | ws_find_window "Thunderbird")

    if test -z "$tb"
        destroy_empty_labeled_space $label

        return 0
    end

    # -------------------------------------------------------------------------
    # 3. Resolve target display
    #    Prefer an external display; if none exists, fall back to internal.
    # -------------------------------------------------------------------------
    set -l target_display (resolve_external_display)

    # -------------------------------------------------------------------------
    # 4. Find or create target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    # -------------------------------------------------------------------------
    # 5. Normalize target space state
    # -------------------------------------------------------------------------
    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    gtd_cleanup_wide_spaces
    gtd_cleanup_solo_spaces
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 6. Move captured Thunderbird window
    # -------------------------------------------------------------------------
    ws_move_app_to_space $target_space "Thunderbird" $tb

    # -------------------------------------------------------------------------
    # 7. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set tb (echo $windows_json_final | ws_find_window "Thunderbird" --space $target_space)

    # -------------------------------------------------------------------------
    # 8. Apply final layout
    #    Keep Thunderbird on the lower half, full width.
    # -------------------------------------------------------------------------
    if test -n "$tb"
        ws_window $tb --grid 2:1:0:1:1:1
    end

    # -------------------------------------------------------------------------
    # 9. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    gtd_cleanup_wide_spaces
    gtd_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

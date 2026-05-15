function gtd_meeting_tall --description "Collect Outlook, Zoom and Teams onto the tall GTD meeting workspace and apply the standard meeting layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_meeting_tall
    #
    # Purpose:
    #   Move meeting-related applications to the GTD meeting workspace in tall
    #   mode and place them into a stable vertical layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
    #
    # Managed apps:
    #   - Microsoft Outlook
    #   - zoom.us
    #   - Microsoft Teams
    #
    # Window selection rules:
    #   - At least one of Outlook, Zoom, or Teams must be present. If none are
    #     present, the workspace is not created.
    #   - Outlook:
    #       Take the first non-minimized Outlook window.
    #   - Zoom:
    #       Prefer a non-minimized main control window and exclude windows whose
    #       title suggests meeting/video/share/screen/mini UI.
    #   - Teams:
    #       Prefer a non-minimized main control window and exclude windows whose
    #       title suggests meeting/video/call/share/screen/mini UI.
    #
    # Layout:
    #   - Zoom    -> upper-left
    #   - Teams   -> upper-right
    #   - Outlook -> lower full width
    #
    # Notes:
    #   - Before entering GTD meeting tall mode, empty GTD wide spaces are
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

    set -l label gtd_meeting_tall
    set -l target_display (resolve_external_display)

    # -------------------------------------------------------------------------
    # 2. First-pass window capture
    #    Outlook, Zoom, and Teams are all primary meeting apps. If none are
    #    present, do not create the workspace.
    # -------------------------------------------------------------------------
    set -l windows_json (yabai -m query --windows)

    set -l out (echo $windows_json | ws_find_window "Microsoft Outlook")

    set -l zoom (echo $windows_json | ws_find_window "zoom.us" --exclude-title meeting --exclude-title video --exclude-title share --exclude-title screen --exclude-title mini)

    set -l teams (echo $windows_json | ws_find_window "Microsoft Teams" --exclude-title meeting --exclude-title video --exclude-title call --exclude-title share --exclude-title screen --exclude-title mini)

    if test -z "$out" -a -z "$zoom" -a -z "$teams"
        destroy_empty_labeled_space $label

        return 0
    end

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
    # 6. First-pass move
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $out $zoom $teams

    # -------------------------------------------------------------------------
    # 7. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set out (echo $windows_json_final | ws_find_window "Microsoft Outlook" --space $target_space)

    set zoom (echo $windows_json_final | ws_find_window "zoom.us" --space $target_space --exclude-title meeting --exclude-title video --exclude-title share --exclude-title screen --exclude-title mini)

    set teams (echo $windows_json_final | ws_find_window "Microsoft Teams" --space $target_space --exclude-title meeting --exclude-title video --exclude-title call --exclude-title share --exclude-title screen --exclude-title mini)

    # -------------------------------------------------------------------------
    # 9. Apply final layout
    #    Keep Zoom on the upper-left, Teams on the upper-right, and Outlook on
    #    the lower full width.
    # -------------------------------------------------------------------------
    if test -n "$zoom"
        ws_window $zoom --grid 2:2:0:0:1:1
    end

    if test -n "$teams"
        ws_window $teams --grid 2:2:1:0:1:1
    end

    if test -n "$out"
        ws_window $out --grid 2:1:0:1:1:1
    end

    # -------------------------------------------------------------------------
    # 10. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    gtd_cleanup_wide_spaces
    gtd_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

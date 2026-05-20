function gtd_meeting_wide --description "Collect Outlook, Zoom and Teams onto the wide GTD meeting workspace and apply the standard meeting layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_meeting_wide
    #
    # Purpose:
    #   Move meeting-related applications to the GTD meeting workspace in wide
    #   mode and place them into a stable horizontal layout.
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
    #   - Outlook -> right 3/5
    #   - Zoom    -> left top
    #   - Teams   -> left bottom
    #
    # Notes:
    #   - Before entering GTD meeting wide mode, empty GTD tall spaces are
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

    set -l label gtd_meeting_wide
    set -l target_display (resolve_external_display)

    # -------------------------------------------------------------------------
    # 2. First-pass window capture
    #    Outlook, Zoom, and Teams are all primary meeting apps. If none are
    #    present, do not create the workspace.
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows "gtd_meeting_wide" initial); or return 1

    set -l out (echo $windows_json | workspace_select_app_window --app "Microsoft Outlook" --movable)
    set -l outlook_status $status

    set -l zoom (echo $windows_json | ws_find_window "zoom.us" --exclude-title meeting --exclude-title video --exclude-title share --exclude-title screen --exclude-title mini)

    set -l teams (echo $windows_json | ws_find_window "Microsoft Teams" --exclude-title meeting --exclude-title video --exclude-title call --exclude-title share --exclude-title screen --exclude-title mini)

    set -l zoom_initial $zoom
    set -l teams_initial $teams

    if test -z "$out" -a -z "$zoom" -a -z "$teams"
        if test "$outlook_status" -eq 2
            return 1
        end

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
    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces
    ws_focus_space $target_space
    sleep 0.15

    if test -z "$out"
        set out (gtd_find_outlook_window gtd_meeting_wide $target_space)
        if test $status -eq 2 -a -z "$zoom" -a -z "$teams"
            return 1
        end
    end

    # -------------------------------------------------------------------------
    # 6. First-pass move
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $out $zoom $teams

    # -------------------------------------------------------------------------
    # 7. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows "gtd_meeting_wide" final); or return 1

    set out (echo $windows_json_final | ws_find_window "Microsoft Outlook" --space $target_space --movable)

    if test -z "$out"
        set out (gtd_find_outlook_window gtd_meeting_wide $target_space)
        if test -n "$out"
            ws_move_windows_to_space $target_space $out
            set windows_json_final (ws_query_windows "gtd_meeting_wide" final); or return 1
            set out (echo $windows_json_final | ws_find_window "Microsoft Outlook" --space $target_space --movable)
        end
    end

    set zoom (echo $windows_json_final | ws_find_window "zoom.us" --space $target_space --exclude-title meeting --exclude-title video --exclude-title share --exclude-title screen --exclude-title mini)

    set teams (echo $windows_json_final | ws_find_window "Microsoft Teams" --space $target_space --exclude-title meeting --exclude-title video --exclude-title call --exclude-title share --exclude-title screen --exclude-title mini)

    if test -z "$zoom" -a -n "$zoom_initial"
        ws_move_windows_to_space $target_space $zoom_initial
        set windows_json_final (ws_query_windows "gtd_meeting_wide" final_zoom_retry); or return 1
        set zoom (echo $windows_json_final | ws_find_window "zoom.us" --space $target_space --exclude-title meeting --exclude-title video --exclude-title share --exclude-title screen --exclude-title mini)
    end

    if test -z "$teams" -a -n "$teams_initial"
        ws_move_windows_to_space $target_space $teams_initial
        set windows_json_final (ws_query_windows "gtd_meeting_wide" final_teams_retry); or return 1
        set teams (echo $windows_json_final | ws_find_window "Microsoft Teams" --space $target_space --exclude-title meeting --exclude-title video --exclude-title call --exclude-title share --exclude-title screen --exclude-title mini)
    end

    # -------------------------------------------------------------------------
    # 9. Apply final layout
    #    Keep Outlook on the right 3/5, Zoom on the upper-left and Teams on
    #    the lower-left.
    # -------------------------------------------------------------------------
    if test -n "$out"
        ws_window $out --grid 2:5:2:0:3:2
    end

    if test -n "$zoom"
        ws_window $zoom --grid 2:5:0:0:2:1
    end

    if test -n "$teams"
        ws_window $teams --grid 2:5:0:1:2:1
    end

    # -------------------------------------------------------------------------
    # 10. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

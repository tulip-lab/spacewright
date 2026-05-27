function gtd_mail_wide --description "Collect Thunderbird onto the wide GTD mail workspace and apply the standard mail layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_mail_wide
    #
    # Purpose:
    #   Move Thunderbird to the GTD mail workspace in wide mode and place it
    #   on the right 3/5 of the target display.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the workspace primary display if no external display is available.
    #
    # Managed app:
    #   - Thunderbird
    #
    # Layout:
    #   - Thunderbird -> right 3/5
    #
    # Notes:
    #   - Before entering GTD mail wide mode, empty GTD tall spaces are cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 1. Cleanup GTD tall spaces before entering wide mode
    # -------------------------------------------------------------------------
    workspace_cleanup_mode_spaces gtd tall
    workspace_cleanup_mode_spaces gtd solo
    set -l label gtd_mail_wide

    # -------------------------------------------------------------------------
    # 2. Find Thunderbird first; if not found, do not create the workspace
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows "gtd_mail_wide" initial); or return 1

    set -l tb (echo $windows_json | ws_find_window "Thunderbird")

    if test -z "$tb"
        destroy_empty_labeled_space $label

        return 0
    end

    # -------------------------------------------------------------------------
    # 3. Resolve target display
    #    Prefer an external display; if none exists, fall back to internal.
    # -------------------------------------------------------------------------
    set -l target_display (resolve_workspace_external_display wide)

    # -------------------------------------------------------------------------
    # 4. Prepare target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (workspace_prepare_labeled_space $label $target_display float gtd:tall gtd:solo)
    or return 1

    # -------------------------------------------------------------------------
    # 6. Move captured Thunderbird window
    # -------------------------------------------------------------------------
    ws_move_app_to_space $target_space "Thunderbird" $tb

    # -------------------------------------------------------------------------
    # 7. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows "gtd_mail_wide" final); or return 1

    set tb (echo $windows_json_final | ws_find_window "Thunderbird" --space $target_space)

    # -------------------------------------------------------------------------
    # 8. Apply final layout
    #    Keep Thunderbird on the right 3/5.
    # -------------------------------------------------------------------------
    if test -n "$tb"
        ws_window $tb --grid 1:5:2:0:3:1
    end

    # -------------------------------------------------------------------------
    # 9. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    workspace_cleanup_mode_spaces gtd tall
    workspace_cleanup_mode_spaces gtd solo
    cleanup_unlabeled_empty_spaces $target_space
end

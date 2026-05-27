function office_slides_tall --description "Collect PowerPoint and ChatGPT onto the tall office slides workspace and apply the standard slides layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   office_slides_tall
    #
    # Purpose:
    #   Move presentation-related applications to the office slides workspace
    #   in tall mode and place them into a stable vertical layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the workspace primary display if no external display is available.
    #
    # Managed apps:
    #   - Microsoft PowerPoint
    #   - ChatGPT
    #
    # Window selection rules:
    #   - Microsoft PowerPoint:
    #       Required primary window. If no non-minimized PowerPoint window
    #       exists, the workspace is not created.
    #   - ChatGPT:
    #       Optional helper window. If present, it is moved into the workspace.
    #
    # Layout:
    #   - ChatGPT    -> upper half
    #   - PowerPoint -> lower half
    #
    # Notes:
    #   - Before entering office slides tall mode, empty office wide spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - If the primary app is missing, it destroys any stale empty labeled
    #     workspace with the same label.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    office_cleanup_wide_spaces

    set -l label office_slides_tall

    # 1. Find PowerPoint first; if not found, do not create the workspace
    set -l windows_json (ws_query_windows "office_slides_tall" initial); or return 1

    set -l ppt_window (echo $windows_json | ws_find_window "Microsoft PowerPoint")

    if test -z "$ppt_window"
        # ---------------------------------------------------------------------
        # No primary PowerPoint window exists.
        # If an old labeled workspace already exists and is empty, destroy it
        # so stale office slides spaces do not accumulate.
        # ---------------------------------------------------------------------
        destroy_empty_labeled_space $label

        return 0
    end

    # 2. Resolve target display
    set -l target_display (resolve_workspace_external_display tall)

    # 3. Prepare target labeled space
    set -l target_space (workspace_prepare_labeled_space $label $target_display float)
    or return 1

    # 5. Move captured windows
    ws_move_windows_to_space $target_space $ppt_window
    set -l chatgpt_window (workspace_capture_app_window --app ChatGPT --caller office_slides_tall --space $target_space)

    # 6. Final capture on target space
    set -l windows_json_final (ws_query_windows "office_slides_tall" final); or return 1

    set ppt_window (echo $windows_json_final | ws_find_window "Microsoft PowerPoint" --space $target_space)

    set chatgpt_window (workspace_find_app_window --app ChatGPT --caller office_slides_tall --space $target_space --no-refresh)

    # 7. Apply final layout
    if test -n "$chatgpt_window"
        ws_window $chatgpt_window --grid 2:1:0:0:1:1
    end

    if test -n "$ppt_window"
        ws_window $ppt_window --grid 2:1:0:1:1:1
    end

    # 8. Final focus and cleanup
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

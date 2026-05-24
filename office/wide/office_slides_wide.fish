function office_slides_wide --description "Collect PowerPoint and ChatGPT onto the wide office slides workspace and apply the standard slides layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   office_slides_wide
    #
    # Purpose:
    #   Move presentation-related applications to the office slides workspace
    #   in wide mode and place them into a stable horizontal layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
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
    #   - ChatGPT    -> left 1/3
    #   - PowerPoint -> right 2/3
    #
    # Notes:
    #   - Before entering office slides wide mode, empty office tall spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - If the primary app is missing, it destroys any stale empty labeled
    #     workspace with the same label.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    office_cleanup_tall_spaces

    set -l label office_slides_wide

    # 1. Find PowerPoint first; if not found, do not create the workspace
    set -l windows_json (ws_query_windows "office_slides_wide" initial); or return 1

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
    set -l target_display (resolve_external_display)

    # 3. Find or create target labeled space
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    # 4. Normalize target space state
    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    ws_focus_space $target_space
    sleep 0.15

    # 5. Move captured windows
    ws_move_windows_to_space $target_space $ppt_window
    set -l chatgpt_window (workspace_capture_app_window --app ChatGPT --caller office_slides_wide --space $target_space)

    # 6. Final capture on target space
    set -l windows_json_final (ws_query_windows "office_slides_wide" final); or return 1

    set ppt_window (echo $windows_json_final | ws_find_window "Microsoft PowerPoint" --space $target_space)

    set chatgpt_window (workspace_find_app_window --app ChatGPT --caller office_slides_wide --space $target_space --no-refresh)

    # 7. Apply final layout
    if test -n "$chatgpt_window"
        ws_window $chatgpt_window --grid 1:3:0:0:1:1
    end

    if test -n "$ppt_window"
        ws_window $ppt_window --grid 1:3:1:0:2:1
    end

    # 8. Final focus and cleanup
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

function research_wide --description "Collect Zotero and ChatGPT onto the wide research workspace and apply the standard research layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   research_wide
    #
    # Purpose:
    #   Move research-related applications to the research workspace in wide
    #   mode and place them into a stable horizontal layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the workspace primary display if no external display is available.
    #
    # Managed apps:
    #   - Zotero
    #   - ChatGPT
    #
    # Window selection rules:
    #   - Zotero:
    #       Required primary window. If no non-minimized Zotero window exists,
    #       the workspace is not created.
    #   - ChatGPT:
    #       Optional helper window. If present, it is moved into the workspace.
    #
    # Layout:
    #   - Zotero  -> left 2/3
    #   - ChatGPT -> right 1/3
    #
    # Notes:
    #   - Before entering research wide mode, empty research tall spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - If the primary app is missing, it destroys any stale empty labeled
    #     workspace with the same label.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    workspace_cleanup_mode_spaces research tall
    workspace_cleanup_mode_spaces research solo
    set -l label research_wide

    # 1. Find Zotero first; if not found, do not create the workspace
    set -l windows_json (ws_query_windows "research_wide" initial); or return 1

    set -l zotero_window (echo $windows_json | ws_find_window "Zotero")

    if test -z "$zotero_window"
        # ---------------------------------------------------------------------
        # No primary Zotero window exists.
        # If an old labeled workspace already exists and is empty, destroy it
        # so stale research spaces do not accumulate.
        # ---------------------------------------------------------------------
        destroy_empty_labeled_space $label

        return 0
    end

    # 2. Resolve target display
    set -l target_display (resolve_workspace_external_display wide)

    # 3. Prepare target labeled space
    set -l target_space (workspace_prepare_labeled_space $label $target_display float research:tall research:solo)
    or return 1

    # 5. Move captured windows
    ws_move_windows_to_space $target_space $zotero_window
    set -l chatgpt_window (workspace_capture_app_window --app ChatGPT --caller research_wide --space $target_space)

    # 6. Final capture on target space
    set -l windows_json_final (ws_query_windows "research_wide" final); or return 1

    set zotero_window (echo $windows_json_final | ws_find_window "Zotero" --space $target_space)

    set chatgpt_window (workspace_find_app_window --app ChatGPT --caller research_wide --space $target_space --no-refresh)

    # 7. Apply final layout
    if test -n "$zotero_window"
        ws_window $zotero_window --grid 1:3:0:0:2:1
    end

    if test -n "$chatgpt_window"
        ws_window $chatgpt_window --grid 1:3:2:0:1:1
    end

    # 8. Final focus and cleanup
    ws_focus_space $target_space
    workspace_cleanup_mode_spaces research tall
    workspace_cleanup_mode_spaces research solo
    cleanup_unlabeled_empty_spaces $target_space
end

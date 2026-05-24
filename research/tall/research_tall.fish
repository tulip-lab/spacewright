function research_tall --description "Collect Zotero and ChatGPT onto the tall research workspace and apply the standard research layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   research_tall
    #
    # Purpose:
    #   Move research-related applications to the research workspace in tall
    #   mode and place them into a stable vertical layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
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
    #   - Zotero  -> upper half
    #   - ChatGPT -> lower half
    #
    # Notes:
    #   - Before entering research tall mode, empty research wide spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - If the primary app is missing, it destroys any stale empty labeled
    #     workspace with the same label.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    research_cleanup_wide_spaces
    research_cleanup_solo_spaces

    set -l label research_tall

    # 1. Find Zotero first; if not found, do not create the workspace
    set -l windows_json (ws_query_windows "research_tall" initial); or return 1

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
    research_cleanup_wide_spaces
    research_cleanup_solo_spaces
    ws_focus_space $target_space
    sleep 0.15

    # 5. Move captured windows
    ws_move_windows_to_space $target_space $zotero_window
    set -l chatgpt_window (workspace_capture_app_window --app ChatGPT --caller research_tall --space $target_space)

    # 6. Final capture on target space
    set -l windows_json_final (ws_query_windows "research_tall" final); or return 1

    set zotero_window (echo $windows_json_final | ws_find_window "Zotero" --space $target_space)

    set chatgpt_window (workspace_find_app_window --app ChatGPT --caller research_tall --space $target_space --no-refresh)

    # 7. Apply final layout
    if test -n "$zotero_window"
        ws_window $zotero_window --grid 2:1:0:0:1:1
    end

    if test -n "$chatgpt_window"
        ws_window $chatgpt_window --grid 2:1:0:1:1:1
    end

    # 8. Final focus and cleanup
    ws_focus_space $target_space
    research_cleanup_wide_spaces
    research_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

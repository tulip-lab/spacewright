function coding_editor_tall --description "Collect VS Code and Codex onto the tall coding editor workspace and apply the standard editor layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   coding_editor_tall
    #
    # Purpose:
    #   Move the primary coding editor window set to the coding editor workspace
    #   in tall mode and place them into a stable vertical layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the workspace primary display if no external display is available.
    #
    # Managed apps:
    #   - Code
    #   - Codex
    #
    # Window selection rules:
    #   - Code:
    #       Required primary window. If no non-minimized VS Code window exists,
    #       the workspace is not created.
    #   - Codex:
    #       Optional helper window. If present, it is moved into the workspace.
    #
    # Layout:
    #   - Codex -> upper half
    #   - Code  -> lower half
    #
    # Notes:
    #   - Before entering coding tall mode, empty coding wide spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 1. Cleanup coding wide spaces before entering tall mode
    # -------------------------------------------------------------------------
    coding_cleanup_wide_spaces
    coding_cleanup_solo_spaces

    set -l label coding_editor_tall

    # -------------------------------------------------------------------------
    # 2. Find Code first; if not found, do not create the workspace
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows "coding_editor_tall" initial); or return 1

    set -l code_window (echo $windows_json | ws_find_window "Code")

    if test -z "$code_window"
        destroy_empty_labeled_space $label

        return 0
    end

    # -------------------------------------------------------------------------
    # 3. Resolve target display
    #    Prefer an external display; if none exists, fall back to internal.
    # -------------------------------------------------------------------------
    set -l target_display (resolve_workspace_external_display tall)

    # -------------------------------------------------------------------------
    # 4. Prepare target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (workspace_prepare_labeled_space $label $target_display float coding_cleanup_wide_spaces coding_cleanup_solo_spaces)
    or return 1

    # -------------------------------------------------------------------------
    # 6. Move captured windows
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $code_window
    set -l codex_window (workspace_capture_app_window --app Codex --caller coding_editor_tall --space $target_space)

    # -------------------------------------------------------------------------
    # 7. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows "coding_editor_tall" final); or return 1

    set code_window (echo $windows_json_final | ws_find_window "Code" --space $target_space)

    set codex_window (workspace_find_app_window --app Codex --caller coding_editor_tall --space $target_space --no-refresh)

    # -------------------------------------------------------------------------
    # 8. Apply final layout
    #    Keep Codex on the upper half and VS Code on the lower half.
    # -------------------------------------------------------------------------
    if test -n "$codex_window"
        ws_window $codex_window --grid 2:1:0:0:1:1
    end

    if test -n "$code_window"
        if test -n "$codex_window"
            ws_window $code_window --grid 2:1:0:1:1:1
        else
            ws_window $code_window --grid 1:1:0:0:1:1
        end
    end

    # -------------------------------------------------------------------------
    # 9. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    coding_cleanup_wide_spaces
    coding_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

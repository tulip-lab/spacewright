function coding_editor_tall --description "Collect VS Code and ChatGPT onto the tall coding editor workspace and apply the standard editor layout"
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
    #   Fall back to the internal display if no external display is available.
    #
    # Managed apps:
    #   - Code
    #   - ChatGPT
    #
    # Window selection rules:
    #   - Code:
    #       Required primary window. If no non-minimized VS Code window exists,
    #       the workspace is not created.
    #   - ChatGPT:
    #       Optional helper window. If present, it is moved into the workspace.
    #
    # Layout:
    #   - ChatGPT -> upper half
    #   - Code    -> lower half
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
    set -l windows_json (yabai -m query --windows)

    set -l code_window (echo $windows_json | ws_find_window "Code")

    if test -z "$code_window"
        destroy_empty_labeled_space $label

        return 0
    end

    # ChatGPT is optional and does not decide whether this workspace should exist
    set -l chatgpt_window (echo $windows_json | ws_find_window "ChatGPT")

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
    coding_cleanup_wide_spaces
    coding_cleanup_solo_spaces
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 6. Move captured windows
    # -------------------------------------------------------------------------
    ws_move_app_pair_to_space \
        $target_space \
        "Code" $code_window \
        "ChatGPT" $chatgpt_window

    # -------------------------------------------------------------------------
    # 7. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set code_window (echo $windows_json_final | ws_find_window "Code" --space $target_space)

    set chatgpt_window (echo $windows_json_final | ws_find_window "ChatGPT" --space $target_space)

    # -------------------------------------------------------------------------
    # 8. Apply final layout
    #    Keep ChatGPT on the upper half and VS Code on the lower half.
    # -------------------------------------------------------------------------
    if test -n "$chatgpt_window"
        ws_window $chatgpt_window --grid 2:1:0:0:1:1
    end

    if test -n "$code_window"
        ws_window $code_window --grid 2:1:0:1:1:1
    end

    # -------------------------------------------------------------------------
    # 9. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    coding_cleanup_wide_spaces
    coding_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

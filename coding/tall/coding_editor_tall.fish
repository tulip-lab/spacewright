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
    #   - It performs a retry pass for window moves.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 1. Cleanup coding wide spaces before entering tall mode
    # -------------------------------------------------------------------------
    coding_cleanup_wide_spaces

    set -l label coding_editor_tall
    set -l internal_uuid (get_internal_display_uuid 2>/dev/null)

    # -------------------------------------------------------------------------
    # 2. Find Code first; if not found, do not create the workspace
    # -------------------------------------------------------------------------
    set -l windows_json (yabai -m query --windows)

    set -l code_window (echo $windows_json | jq -r '
        .[]
        | select(.app=="Code")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -z "$code_window"
        return 0
    end

    # ChatGPT is optional and does not decide whether this workspace should exist
    set -l chatgpt_window (echo $windows_json | jq -r '
        .[]
        | select(.app=="ChatGPT")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    # -------------------------------------------------------------------------
    # 3. Resolve target display
    #    Prefer an external display; if none exists, fall back to internal.
    # -------------------------------------------------------------------------
    set -l displays_json (yabai -m query --displays)

    set -l target_display (echo $displays_json | jq -r --arg uuid "$internal_uuid" '
        .[]
        | select(.uuid != $uuid)
        | .index
    ' | head -n 1)

    if test -z "$target_display"
        set target_display (resolve_target_display $internal_uuid 1)
    end

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
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 6. First-pass move
    # -------------------------------------------------------------------------
    if test -n "$code_window"
        yabai -m window $code_window --space $target_space
    end

    if test -n "$chatgpt_window"
        yabai -m window $chatgpt_window --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 7. Retry pass for windows that did not move successfully
    # -------------------------------------------------------------------------
    set -l windows_json_retry (yabai -m query --windows)

    set -l code_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Code")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l chatgpt_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="ChatGPT")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -n "$code_retry"
        yabai -m window $code_retry --space $target_space
    end

    if test -n "$chatgpt_retry"
        yabai -m window $chatgpt_retry --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 8. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set code_window (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Code")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set chatgpt_window (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="ChatGPT")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    # -------------------------------------------------------------------------
    # 9. Apply final layout
    #    Keep ChatGPT on the upper half and VS Code on the lower half.
    # -------------------------------------------------------------------------
    if test -n "$chatgpt_window"
        yabai -m window $chatgpt_window --grid 2:1:0:0:1:1
    end

    if test -n "$code_window"
        yabai -m window $code_window --grid 2:1:0:1:1:1
    end

    # -------------------------------------------------------------------------
    # 10. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_display
end
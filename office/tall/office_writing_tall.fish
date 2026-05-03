function office_writing_tall --description "Collect Word and ChatGPT onto the tall office writing workspace and apply the standard writing layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   office_writing_tall
    #
    # Purpose:
    #   Move writing-related applications to the office writing workspace in
    #   tall mode and place them into a stable vertical layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
    #
    # Managed apps:
    #   - Microsoft Word
    #   - ChatGPT
    #
    # Window selection rules:
    #   - Microsoft Word:
    #       Required primary window. If no non-minimized Word window exists,
    #       the workspace is not created.
    #   - ChatGPT:
    #       Optional helper window. If present, it is moved into the workspace.
    #
    # Layout:
    #   - ChatGPT -> upper half
    #   - Word    -> lower half
    #
    # Notes:
    #   - Before entering office writing tall mode, empty office wide spaces
    #     are cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It performs a retry pass for window moves.
    #   - If the primary app is missing, it destroys any stale empty labeled
    #     workspace with the same label.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    office_cleanup_wide_spaces

    set -l label office_writing_tall
    set -l internal_uuid (get_internal_display_uuid 2>/dev/null)

    # 1. Find Word first; if not found, do not create the workspace
    set -l windows_json (yabai -m query --windows)

    set -l word_window (echo $windows_json | jq -r '
        .[]
        | select(.app=="Microsoft Word")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -z "$word_window"
        # ---------------------------------------------------------------------
        # No primary Word window exists.
        # If an old labeled workspace already exists and is empty, destroy it
        # so stale office writing spaces do not accumulate.
        # ---------------------------------------------------------------------
        set -l stale_space (yabai -m query --spaces | jq -r --arg label "$label" '
            .[]
            | select(.label==$label)
            | select((.windows | length) == 0)
            | .index
        ' | head -n 1)

        if test -n "$stale_space"
            yabai -m space $stale_space --destroy
        end

        return 0
    end

    # ChatGPT is optional and does not decide whether this workspace should exist
    set -l chatgpt_window (echo $windows_json | jq -r '
        .[]
        | select(.app=="ChatGPT")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    # 2. Resolve target display
    set -l displays_json (yabai -m query --displays)

    set -l target_display (echo $displays_json | jq -r --arg uuid "$internal_uuid" '
        .[]
        | select(.uuid != $uuid)
        | .index
    ' | head -n 1)

    if test -z "$target_display"
        set target_display (resolve_target_display $internal_uuid 1)
    end

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

    # 5. First-pass move
    if test -n "$word_window"
        yabai -m window $word_window --space $target_space
    end

    if test -n "$chatgpt_window"
        yabai -m window $chatgpt_window --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # 6. Retry pass for windows that did not move successfully
    set -l windows_json_retry (yabai -m query --windows)

    set -l word_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Microsoft Word")
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

    if test -n "$word_retry"
        yabai -m window $word_retry --space $target_space
    end

    if test -n "$chatgpt_retry"
        yabai -m window $chatgpt_retry --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # 7. Final capture on target space
    set -l windows_json_final (yabai -m query --windows)

    set word_window (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Microsoft Word")
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

    # 8. Apply final layout
    if test -n "$chatgpt_window"
        yabai -m window $chatgpt_window --grid 2:1:0:0:1:1
    end

    if test -n "$word_window"
        yabai -m window $word_window --grid 2:1:0:1:1:1
    end

    # 9. Final focus and cleanup
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_display
end
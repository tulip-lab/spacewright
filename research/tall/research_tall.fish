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
    #   - It performs a retry pass for window moves.
    #   - If the primary app is missing, it destroys any stale empty labeled
    #     workspace with the same label.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    research_cleanup_wide_spaces

    set -l label research_tall

    # 1. Find Zotero first; if not found, do not create the workspace
    set -l windows_json (yabai -m query --windows)

    set -l zotero_window (echo $windows_json | jq -r '
        .[]
        | select(.app=="Zotero")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -z "$zotero_window"
        # ---------------------------------------------------------------------
        # No primary Zotero window exists.
        # If an old labeled workspace already exists and is empty, destroy it
        # so stale research spaces do not accumulate.
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

    # 5. First-pass move
    if test -n "$zotero_window"
        yabai -m window $zotero_window --space $target_space
    end

    if test -n "$chatgpt_window"
        yabai -m window $chatgpt_window --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # 6. Retry pass
    set -l windows_json_retry (yabai -m query --windows)

    set -l zotero_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Zotero")
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

    if test -n "$zotero_retry"
        yabai -m window $zotero_retry --space $target_space
    end

    if test -n "$chatgpt_retry"
        yabai -m window $chatgpt_retry --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # 7. Final capture on target space
    set -l windows_json_final (yabai -m query --windows)

    set zotero_window (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Zotero")
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
    if test -n "$zotero_window"
        yabai -m window $zotero_window --grid 2:1:0:0:1:1
    end

    if test -n "$chatgpt_window"
        yabai -m window $chatgpt_window --grid 2:1:0:1:1:1
    end

    # 9. Final focus and cleanup
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_display
end
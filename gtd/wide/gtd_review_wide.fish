function gtd_review_wide --description "Collect review-related windows onto the wide GTD review workspace and apply the standard review layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_review_wide
    #
    # Purpose:
    #   Move review-related applications to the GTD review workspace in wide
    #   mode and place them into a stable review layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
    #
    # Managed apps:
    #   - Finder
    #   - Preview
    #   - ChatGPT
    #   - Notes
    #
    # Window selection rules:
    #   - Preview:
    #       Required primary window. If no non-minimized Preview window exists,
    #       the workspace is not created.
    #   - Notes:
    #       Prefer a non-minimized window whose title is not empty.
    #       If none is found, fall back to any non-minimized Notes window.
    #   - Finder / ChatGPT:
    #       Use the first non-minimized window if available.
    #
    # Layout:
    #   - Finder  -> left 1/4
    #   - Preview -> middle 3/8
    #   - ChatGPT -> right upper 3/8
    #   - Notes   -> right lower 3/8
    #
    # Notes:
    #   - Before entering GTD review wide mode, empty GTD tall spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It performs a retry pass for window moves.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 1. Cleanup GTD tall spaces before entering wide mode
    # -------------------------------------------------------------------------
    gtd_cleanup_tall_spaces

    set -l label gtd_review_wide
    set -l internal_uuid "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    # -------------------------------------------------------------------------
    # 2. Find Preview first; if not found, do not create the workspace
    # -------------------------------------------------------------------------
    set -l windows_json (yabai -m query --windows)

    set -l preview (echo $windows_json | jq -r '
        .[]
        | select(.app=="Preview")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -z "$preview"
        return 0
    end

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
    # 6. First-pass window capture
    # -------------------------------------------------------------------------
    set -l finder (echo $windows_json | jq -r '
        .[]
        | select(.app=="Finder")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l chatgpt (echo $windows_json | jq -r '
        .[]
        | select(.app=="ChatGPT")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    # Notes: prefer non-empty title
    set -l notes (echo $windows_json | jq -r '
        .[]
        | select(.app=="Notes")
        | select(.["is-minimized"]==false)
        | select(.title != null and .title != "")
        | .id
    ' | head -n 1)

    if test -z "$notes"
        set notes (echo $windows_json | jq -r '
            .[]
            | select(.app=="Notes")
            | select(.["is-minimized"]==false)
            | .id
        ' | head -n 1)
    end

    # -------------------------------------------------------------------------
    # 7. First-pass move
    # -------------------------------------------------------------------------
    if test -n "$finder"
        yabai -m window $finder --space $target_space
    end

    if test -n "$preview"
        yabai -m window $preview --space $target_space
    end

    if test -n "$chatgpt"
        yabai -m window $chatgpt --space $target_space
    end

    if test -n "$notes"
        yabai -m window $notes --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 8. Retry pass for windows that did not move successfully
    # -------------------------------------------------------------------------
    set -l windows_json_retry (yabai -m query --windows)

    set -l finder_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Finder")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l preview_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Preview")
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

    set -l notes_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Notes")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | select(.title != null and .title != "")
        | .id
    ' | head -n 1)

    if test -z "$notes_retry"
        set notes_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
            .[]
            | select(.app=="Notes")
            | select(.space!=$s)
            | select(.["is-minimized"]==false)
            | .id
        ' | head -n 1)
    end

    if test -n "$finder_retry"
        yabai -m window $finder_retry --space $target_space
    end

    if test -n "$preview_retry"
        yabai -m window $preview_retry --space $target_space
    end

    if test -n "$chatgpt_retry"
        yabai -m window $chatgpt_retry --space $target_space
    end

    if test -n "$notes_retry"
        yabai -m window $notes_retry --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 9. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set finder (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Finder")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set preview (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Preview")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set chatgpt (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="ChatGPT")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set notes (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Notes")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | select(.title != null and .title != "")
        | .id
    ' | head -n 1)

    if test -z "$notes"
        set notes (echo $windows_json_final | jq -r --argjson s $target_space '
            .[]
            | select(.app=="Notes")
            | select(.space==$s)
            | select(.["is-minimized"]==false)
            | .id
        ' | head -n 1)
    end

    # -------------------------------------------------------------------------
    # 10. Apply final layout
    #     Left 1/4 Finder, middle 3/8 Preview,
    #     right upper 3/8 ChatGPT, right lower 3/8 Notes.
    # -------------------------------------------------------------------------
    if test -n "$finder"
        yabai -m window $finder --grid 2:8:0:0:2:2
    end

    if test -n "$preview"
        yabai -m window $preview --grid 2:8:2:0:3:2
    end

    if test -n "$chatgpt"
        yabai -m window $chatgpt --grid 2:8:5:0:3:1
    end

    if test -n "$notes"
        yabai -m window $notes --grid 2:8:5:1:3:1
    end

    # -------------------------------------------------------------------------
    # 11. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_display
end
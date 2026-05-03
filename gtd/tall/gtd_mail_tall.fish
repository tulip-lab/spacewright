function gtd_mail_tall --description "Collect Thunderbird onto the tall GTD mail workspace and apply the standard tall mail layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_mail_tall
    #
    # Purpose:
    #   Move Thunderbird to the GTD mail workspace in tall mode and place it
    #   on the lower half of the target display.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
    #
    # Managed app:
    #   - Thunderbird
    #
    # Layout:
    #   - Thunderbird -> lower half, full width
    #
    # Notes:
    #   - Before entering GTD mail tall mode, empty GTD wide spaces are cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It performs a retry pass for window moves.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 1. Cleanup GTD wide spaces before entering tall mode
    # -------------------------------------------------------------------------
    gtd_cleanup_wide_spaces

    set -l label gtd_mail_tall
    set -l internal_uuid (get_internal_display_uuid 2>/dev/null)

    # -------------------------------------------------------------------------
    # 2. Find Thunderbird first; if not found, do not create the workspace
    # -------------------------------------------------------------------------
    set -l windows_json (yabai -m query --windows)

    set -l tb (echo $windows_json | jq -r '
        .[]
        | select(.app=="Thunderbird")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -z "$tb"
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
    # 6. First-pass move
    # -------------------------------------------------------------------------
    if test -n "$tb"
        yabai -m window $tb --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 7. Retry pass if Thunderbird did not move successfully
    # -------------------------------------------------------------------------
    set -l windows_json_retry (yabai -m query --windows)

    set -l tb_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Thunderbird")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -n "$tb_retry"
        yabai -m window $tb_retry --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 8. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set tb (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Thunderbird")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    # -------------------------------------------------------------------------
    # 9. Apply final layout
    #    Keep Thunderbird on the lower half, full width.
    # -------------------------------------------------------------------------
    if test -n "$tb"
        yabai -m window $tb --grid 2:1:0:1:1:1
    end

    # -------------------------------------------------------------------------
    # 10. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_display
end
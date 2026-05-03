function gtd_support_tall --description "Collect Notes and Dia onto the tall GTD support workspace and apply the standard support layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_support_tall
    #
    # Purpose:
    #   Move support-related applications to the GTD support workspace in tall
    #   mode and place them into a stable vertical layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
    #
    # Managed apps:
    #   - Notes
    #   - Dia
    #
    # Window selection rules:
    #   - Notes:
    #       Prefer a non-minimized window whose title is not empty.
    #       If none is found, fall back to any non-minimized Notes window.
    #   - Dia:
    #       Prefer a non-minimized window whose title is not empty and does not
    #       contain "New Tab".
    #       If none is found, fall back to any non-minimized Dia window.
    #
    # Layout:
    #   - Notes -> top half
    #   - Dia   -> bottom half
    #
    # Notes:
    #   - Before entering GTD support tall mode, empty GTD wide spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It performs a retry pass for window moves.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 1. Cleanup GTD wide spaces before entering tall mode
    # -------------------------------------------------------------------------
    gtd_cleanup_wide_spaces

    set -l label gtd_support_tall
    set -l internal_uuid "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    # -------------------------------------------------------------------------
    # 2. Resolve target display
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
    # 3. Find or create target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    # -------------------------------------------------------------------------
    # 4. Normalize target space state
    # -------------------------------------------------------------------------
    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 5. First-pass window capture
    # -------------------------------------------------------------------------
    set -l windows_json (yabai -m query --windows)

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

    # Dia: prefer non-empty title and not "New Tab"
    set -l dia (echo $windows_json | jq -r '
        .[]
        | select(.app=="Dia")
        | select(.["is-minimized"]==false)
        | select(.title != null and .title != "")
        | select((.title | ascii_downcase | contains("new tab")) | not)
        | .id
    ' | head -n 1)

    if test -z "$dia"
        set dia (echo $windows_json | jq -r '
            .[]
            | select(.app=="Dia")
            | select(.["is-minimized"]==false)
            | .id
        ' | head -n 1)
    end

    # -------------------------------------------------------------------------
    # 6. First-pass move
    # -------------------------------------------------------------------------
    if test -n "$notes"
        yabai -m window $notes --space $target_space
    end

    if test -n "$dia"
        yabai -m window $dia --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 7. Retry pass for windows that did not move successfully
    # -------------------------------------------------------------------------
    set -l windows_json_retry (yabai -m query --windows)

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

    set -l dia_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Dia")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | select(.title != null and .title != "")
        | select((.title | ascii_downcase | contains("new tab")) | not)
        | .id
    ' | head -n 1)

    if test -z "$dia_retry"
        set dia_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
            .[]
            | select(.app=="Dia")
            | select(.space!=$s)
            | select(.["is-minimized"]==false)
            | .id
        ' | head -n 1)
    end

    if test -n "$notes_retry"
        yabai -m window $notes_retry --space $target_space
    end

    if test -n "$dia_retry"
        yabai -m window $dia_retry --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 8. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

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

    set dia (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Dia")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | select(.title != null and .title != "")
        | select((.title | ascii_downcase | contains("new tab")) | not)
        | .id
    ' | head -n 1)

    if test -z "$dia"
        set dia (echo $windows_json_final | jq -r --argjson s $target_space '
            .[]
            | select(.app=="Dia")
            | select(.space==$s)
            | select(.["is-minimized"]==false)
            | .id
        ' | head -n 1)
    end

    # -------------------------------------------------------------------------
    # 9. Apply final layout
    #    Keep Notes on top and Dia on bottom.
    # -------------------------------------------------------------------------
    if test -n "$notes"
        yabai -m window $notes --grid 2:1:0:0:1:1
    end

    if test -n "$dia"
        yabai -m window $dia --grid 2:1:0:1:1:1
    end

    # -------------------------------------------------------------------------
    # 10. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_display
end
function gtd_meeting_wide --description "Collect Outlook, Zoom and Teams onto the wide GTD meeting workspace and apply the standard meeting layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_meeting_wide
    #
    # Purpose:
    #   Move meeting-related applications to the GTD meeting workspace in wide
    #   mode and place them into a stable horizontal layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
    #
    # Managed apps:
    #   - Microsoft Outlook
    #   - zoom.us
    #   - Microsoft Teams
    #
    # Window selection rules:
    #   - Outlook:
    #       Take the first non-minimized Outlook window.
    #   - Zoom:
    #       Prefer a non-minimized main control window and exclude windows whose
    #       title suggests meeting/video/share/screen/mini UI.
    #   - Teams:
    #       Prefer a non-minimized main control window and exclude windows whose
    #       title suggests meeting/video/call/share/screen/mini UI.
    #
    # Layout:
    #   - Outlook -> right 3/5
    #   - Zoom    -> left top
    #   - Teams   -> left bottom
    #
    # Notes:
    #   - Before entering GTD meeting wide mode, empty GTD tall spaces are
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

    set -l label gtd_meeting_wide
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

    set -l out (echo $windows_json | jq -r '
        .[]
        | select(.app=="Microsoft Outlook")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l zoom (echo $windows_json | jq -r '
        .[]
        | select(.app=="zoom.us")
        | select(.["is-minimized"]==false)
        | select((.title | ascii_downcase | contains("meeting")) | not)
        | select((.title | ascii_downcase | contains("video"))   | not)
        | select((.title | ascii_downcase | contains("share"))   | not)
        | select((.title | ascii_downcase | contains("screen"))  | not)
        | select((.title | ascii_downcase | contains("mini"))    | not)
        | .id
    ' | head -n 1)

    set -l teams (echo $windows_json | jq -r '
        .[]
        | select(.app=="Microsoft Teams")
        | select(.["is-minimized"]==false)
        | select((.title | ascii_downcase | contains("meeting")) | not)
        | select((.title | ascii_downcase | contains("video"))   | not)
        | select((.title | ascii_downcase | contains("call"))    | not)
        | select((.title | ascii_downcase | contains("share"))   | not)
        | select((.title | ascii_downcase | contains("screen"))  | not)
        | select((.title | ascii_downcase | contains("mini"))    | not)
        | .id
    ' | head -n 1)

    # -------------------------------------------------------------------------
    # 6. First-pass move
    # -------------------------------------------------------------------------
    if test -n "$out"
        yabai -m window $out --space $target_space
    end

    if test -n "$zoom"
        yabai -m window $zoom --space $target_space
    end

    if test -n "$teams"
        yabai -m window $teams --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 7. Retry pass for windows that did not move successfully
    # -------------------------------------------------------------------------
    set -l windows_json_retry (yabai -m query --windows)

    set -l out_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Microsoft Outlook")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l zoom_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="zoom.us")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | select((.title | ascii_downcase | contains("meeting")) | not)
        | select((.title | ascii_downcase | contains("video"))   | not)
        | select((.title | ascii_downcase | contains("share"))   | not)
        | select((.title | ascii_downcase | contains("screen"))  | not)
        | select((.title | ascii_downcase | contains("mini"))    | not)
        | .id
    ' | head -n 1)

    set -l teams_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Microsoft Teams")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | select((.title | ascii_downcase | contains("meeting")) | not)
        | select((.title | ascii_downcase | contains("video"))   | not)
        | select((.title | ascii_downcase | contains("call"))    | not)
        | select((.title | ascii_downcase | contains("share"))   | not)
        | select((.title | ascii_downcase | contains("screen"))  | not)
        | select((.title | ascii_downcase | contains("mini"))    | not)
        | .id
    ' | head -n 1)

    if test -n "$out_retry"
        yabai -m window $out_retry --space $target_space
    end

    if test -n "$zoom_retry"
        yabai -m window $zoom_retry --space $target_space
    end

    if test -n "$teams_retry"
        yabai -m window $teams_retry --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 8. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set out (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Microsoft Outlook")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set zoom (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="zoom.us")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | select((.title | ascii_downcase | contains("meeting")) | not)
        | select((.title | ascii_downcase | contains("video"))   | not)
        | select((.title | ascii_downcase | contains("share"))   | not)
        | select((.title | ascii_downcase | contains("screen"))  | not)
        | select((.title | ascii_downcase | contains("mini"))    | not)
        | .id
    ' | head -n 1)

    set teams (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Microsoft Teams")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | select((.title | ascii_downcase | contains("meeting")) | not)
        | select((.title | ascii_downcase | contains("video"))   | not)
        | select((.title | ascii_downcase | contains("call"))    | not)
        | select((.title | ascii_downcase | contains("share"))   | not)
        | select((.title | ascii_downcase | contains("screen"))  | not)
        | select((.title | ascii_downcase | contains("mini"))    | not)
        | .id
    ' | head -n 1)

    # -------------------------------------------------------------------------
    # 9. Apply final layout
    #    Keep Outlook on the right 3/5, Zoom on the upper-left and Teams on
    #    the lower-left.
    # -------------------------------------------------------------------------
    if test -n "$out"
        yabai -m window $out --grid 2:5:2:0:3:2
    end

    if test -n "$zoom"
        yabai -m window $zoom --grid 2:5:0:0:2:1
    end

    if test -n "$teams"
        yabai -m window $teams --grid 2:5:0:1:2:1
    end

    # -------------------------------------------------------------------------
    # 10. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_display
end
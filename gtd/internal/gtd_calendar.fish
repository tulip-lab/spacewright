function gtd_calendar --description "Collect Calendar and Reminders onto the internal display and apply the standard GTD calendar layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_calendar
    #
    # Purpose:
    #   Gather Calendar-related applications onto the internal display and place
    #   them into a stable GTD calendar layout.
    #
    # Target display:
    #   Internal display identified by UUID.
    #
    # Managed apps:
    #   - Calendar
    #   - Reminders
    #
    # Layout:
    #   - Calendar  -> left half
    #   - Reminders -> right half
    #
    # Notes:
    #   - The function is designed to be re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It performs a retry pass for window moves.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    set -l label gtd_calendar

    # -------------------------------------------------------------------------
    # 1. Resolve target display and target space
    # -------------------------------------------------------------------------
    set -l target_display (resolve_internal_display)
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    # -------------------------------------------------------------------------
    # 2. Normalize target space state
    # -------------------------------------------------------------------------
    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 3. First-pass window capture
    # -------------------------------------------------------------------------
    set -l windows_json (yabai -m query --windows)

    set -l calendar (echo $windows_json | jq -r '
        .[]
        | select(.app=="Calendar")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l reminders (echo $windows_json | jq -r '
        .[]
        | select(.app=="Reminders")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    # -------------------------------------------------------------------------
    # 4. First-pass move
    # -------------------------------------------------------------------------
    if test -n "$calendar"
        yabai -m window $calendar --space $target_space
    end

    if test -n "$reminders"
        yabai -m window $reminders --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 5. Retry pass for windows that did not move successfully
    # -------------------------------------------------------------------------
    set -l windows_json_retry (yabai -m query --windows)

    set -l calendar_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Calendar")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l reminders_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Reminders")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -n "$calendar_retry"
        yabai -m window $calendar_retry --space $target_space
    end

    if test -n "$reminders_retry"
        yabai -m window $reminders_retry --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 6. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set calendar (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Calendar")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set reminders (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Reminders")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    # -------------------------------------------------------------------------
    # 7. Apply final layout
    # -------------------------------------------------------------------------
    if test -n "$calendar"
        yabai -m window $calendar --grid 1:2:0:0:1:1
    end

    if test -n "$reminders"
        yabai -m window $reminders --grid 1:2:1:0:1:1
    end

    # -------------------------------------------------------------------------
    # 8. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end
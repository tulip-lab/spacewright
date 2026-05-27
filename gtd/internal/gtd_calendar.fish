function gtd_calendar --description "Collect Calendar and Reminders onto the workspace primary display and apply the standard GTD calendar layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_calendar
    #
    # Purpose:
    #   Gather Calendar-related applications onto the workspace primary display and place
    #   them into a stable GTD calendar layout.
    #
    # Target display:
    #   Workspace primary display identified by UUID.
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
    #   - It moves only the initially captured window IDs.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    set -l label gtd_calendar

    # -------------------------------------------------------------------------
    # 1. First-pass window capture
    #    At least one calendar app must exist before creating the workspace.
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows gtd_calendar initial); or return 1

    set -l calendar (echo $windows_json | ws_find_window "Calendar")

    set -l reminders (echo $windows_json | ws_find_window "Reminders")

    if test -z "$calendar" -a -z "$reminders"
        destroy_empty_labeled_space $label

        return 0
    end

    # -------------------------------------------------------------------------
    # 2. Resolve target display and target space
    # -------------------------------------------------------------------------
    set -l target_display (resolve_workspace_primary_display)
    set -l target_space (workspace_prepare_labeled_space $label $target_display float)
    or return 1

    # -------------------------------------------------------------------------
    # 4. First-pass move
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $calendar $reminders

    # -------------------------------------------------------------------------
    # 5. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows gtd_calendar final); or return 1

    set calendar (echo $windows_json_final | ws_find_window "Calendar" --space $target_space)

    set reminders (echo $windows_json_final | ws_find_window "Reminders" --space $target_space)

    # -------------------------------------------------------------------------
    # 7. Apply final layout
    # -------------------------------------------------------------------------
    if test -n "$calendar"
        ws_window $calendar --grid 1:2:0:0:1:1
    end

    if test -n "$reminders"
        ws_window $reminders --grid 1:2:1:0:1:1
    end

    # -------------------------------------------------------------------------
    # 8. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

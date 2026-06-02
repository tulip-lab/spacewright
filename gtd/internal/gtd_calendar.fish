function gtd_calendar --description "Collect Calendar and Reminders onto the workspace primary display and apply the standard GTD calendar layout"
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=gtd_calendar\n"
        printf "label=%s\n" gtd_calendar
        printf "display=%s\n" primary
        printf "apps=%s,%s\n" (workspace_app_name calendar) (workspace_app_name reminders)
        return 0
    end

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
    #   - It retries Calendar and Reminders once if they do not land on target.
    #   - It uses Calendar's current space when Calendar remains non-movable.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    set -l label gtd_calendar
    set -l calendar_apps_json (workspace_app_names_json calendar)
    or return 1

    # -------------------------------------------------------------------------
    # 1. First-pass window capture
    #    At least one calendar app must exist before creating the workspace.
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows gtd_calendar initial); or return 1

    set -l calendar_space_fallback_used 0
    set -l calendar_status 0
    set -l calendar
    set -l calendar_fallback_window
    set -l calendar_fallback_space
    set -l calendar_fallback_display

    set -l calendar_initial_info (echo $windows_json | ws_jq -r --argjson apps "$calendar_apps_json" '
        first(
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.["is-minimized"]==false)
            | [.id, .space, .display, .["can-move"]]
            | @tsv
        ) // empty
    ')
    if test $status -ne 0
        return 1
    end

    if test -n "$calendar_initial_info"
        set -l calendar_initial_parts (string split \t -- "$calendar_initial_info")
        if test "$calendar_initial_parts[4]" = true
            set calendar $calendar_initial_parts[1]
            rm -f /tmp/workspace-ws-window-bad/$calendar 2>/dev/null
        else
            set calendar_status 2
            set calendar_fallback_window $calendar_initial_parts[1]
            set calendar_fallback_space $calendar_initial_parts[2]
            set calendar_fallback_display $calendar_initial_parts[3]
        end
    else
        set calendar (workspace_find_app_key_window --app-key calendar --caller $label --quiet-unmovable)
        set calendar_status $status
        if test "$calendar_status" -eq 1
            return 1
        end
    end

    if test -z "$calendar" -a "$calendar_status" -eq 2 -a -z "$calendar_fallback_window"
        set -l calendar_fallback_info (workspace_app_key_space_fallback_info \
            --app-key calendar \
            --caller $label \
            --phase calendar_space_fallback)
        set -l calendar_fallback_status $status

        if test "$calendar_fallback_status" -eq 1
            return 1
        end

        if test -z "$calendar_fallback_info"
            echo "[WARN] $label found Calendar, but could not identify a Calendar space fallback" >&2
            return 1
        end

        set -l calendar_fallback_parts (string split \t -- "$calendar_fallback_info")
        set calendar_fallback_window $calendar_fallback_parts[1]
        set calendar_fallback_space $calendar_fallback_parts[2]
        set calendar_fallback_display $calendar_fallback_parts[3]

        if test -z "$calendar_fallback_window" -o -z "$calendar_fallback_space" -o -z "$calendar_fallback_display"
            echo "[WARN] $label found Calendar, but its fallback space metadata was incomplete" >&2
            return 1
        end
    end

    set -l reminders (workspace_find_app_key_window --app-key reminders --caller $label)
    set -l reminders_status $status
    if test "$reminders_status" -eq 1
        return 1
    end

    if test -z "$calendar" -a -z "$calendar_fallback_window" -a -z "$reminders"
        if test "$calendar_status" -eq 2 -o "$reminders_status" -eq 2
            return 1
        end

        destroy_empty_labeled_space $label

        return 0
    end

    # -------------------------------------------------------------------------
    # 2. Resolve target display and target space
    # -------------------------------------------------------------------------
    set -l target_display (resolve_workspace_primary_display)
    set -l target_space

    if test -n "$calendar_fallback_space"
        set calendar_space_fallback_used 1
        set target_space $calendar_fallback_space
        set calendar $calendar_fallback_window

        set target_space (workspace_focus_space_fallback \
            --label $label \
            --space $target_space \
            --source-display $calendar_fallback_display \
            --target-display $target_display \
            --layout float \
            --phase calendar-space-fallback)
        or return 1
    else
        set target_space (workspace_prepare_labeled_space $label $target_display float)
        or return 1
    end

    # -------------------------------------------------------------------------
    # 4. First-pass move
    # -------------------------------------------------------------------------
    if test "$calendar_space_fallback_used" -eq 1
        ws_move_windows_to_space $target_space $reminders
    else
        ws_move_windows_to_space $target_space $calendar $reminders
    end

    # -------------------------------------------------------------------------
    # 5. Final capture on target space
    # -------------------------------------------------------------------------
    if test "$calendar_space_fallback_used" -eq 1
        set -l windows_json_final (ws_query_windows gtd_calendar final_calendar_fallback)
        or return 1

        set calendar (echo $windows_json_final | ws_jq -r --argjson apps "$calendar_apps_json" --argjson s $target_space '
            first(
                .[]
                | select(.app as $app | $apps | index($app))
                | select(.space==$s)
                | select(.["is-minimized"]==false)
                | .id
            ) // empty
        ')
    else
        set calendar (workspace_find_app_key_window --app-key calendar --caller $label --space $target_space --no-refresh --target-only)
    end

    set reminders (workspace_find_app_key_window --app-key reminders --caller $label --space $target_space --no-refresh --target-only)

    if test -z "$calendar" -a "$calendar_space_fallback_used" -ne 1
        set calendar (workspace_find_app_key_window --app-key calendar --caller $label)
        set calendar_status $status
        if test "$calendar_status" -eq 1
            return 1
        end

        if test -n "$calendar"
            ws_move_windows_to_space $target_space $calendar
            set calendar (workspace_find_app_key_window --app-key calendar --caller $label --space $target_space --no-refresh --target-only)
        end
    end

    if test -z "$reminders"
        set reminders (workspace_find_app_key_window --app-key reminders --caller $label)
        set reminders_status $status
        if test "$reminders_status" -eq 1
            return 1
        end

        if test -n "$reminders"
            ws_move_windows_to_space $target_space $reminders
            set reminders (workspace_find_app_key_window --app-key reminders --caller $label --space $target_space --no-refresh --target-only)
        end
    end

    # -------------------------------------------------------------------------
    # 7. Apply final layout
    # -------------------------------------------------------------------------
    if test -n "$calendar"
        if test "$calendar_space_fallback_used" -eq 1
            workspace_apply_app_key_grid_bounds \
                --app-key calendar \
                --display $target_display \
                --grid 1:2:0:0:1:1 \
                --caller $label
        else
            ws_window $calendar --grid 1:2:0:0:1:1
        end
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

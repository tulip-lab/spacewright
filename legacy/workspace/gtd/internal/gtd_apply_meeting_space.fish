function gtd_apply_meeting_space --description "Apply a GTD meeting workspace for Zoom and Teams"
    argparse \
        'label=' \
        'display=' \
        'zoom-grid=' \
        'teams-grid=' \
        dry-run \
        -- $argv
    or return 1

    if not set -q _flag_label; or not set -q _flag_display
        echo "usage: gtd_apply_meeting_space --label <label> --display <primary|wide|tall> --zoom-grid <grid> --teams-grid <grid> [cleanup-spec ...]" >&2
        return 2
    end

    set -l cleanup_specs $argv

    if set -q _flag_dry_run
        set -l zoom_apps (string join '|' (workspace_app_names zoom))
        set -l teams_apps (string join '|' (workspace_app_names teams))
        printf "dry_run=gtd_apply_meeting_space\n"
        printf "label=%s\n" "$_flag_label"
        printf "display=%s\n" "$_flag_display"
        printf "apps=%s,%s\n" "$zoom_apps" "$teams_apps"
        printf "zoom_grid=%s\n" "$_flag_zoom_grid"
        printf "teams_grid=%s\n" "$_flag_teams_grid"
        printf "cleanup=%s\n" "$cleanup_specs"
        return 0
    end

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    set -l target_display (workspace_resolve_display_role $_flag_display)
    or return $status

    set -l zoom_apps_json (workspace_app_names_json zoom)
    or return 1
    set -l teams_apps_json (workspace_app_names_json teams)
    or return 1

    set -l zoom_windows (gtd_find_zoom_windows $_flag_label --no-refresh)
    set -l zoom_status $status
    set -l teams_windows (gtd_find_teams_windows $_flag_label --no-refresh)
    set -l teams_status $status
    set -l zoom_initial $zoom_windows
    set -l teams_initial $teams_windows

    set -l zoom_space_fallback_used 0
    set -l zoom_skip_final_bounds_fallback 0
    set -l zoom_fallback_window
    set -l zoom_fallback_space
    set -l zoom_fallback_display

    if test (count $zoom_windows) -eq 0
        set zoom_windows (gtd_find_zoom_windows $_flag_label --quiet-unmovable)
        set zoom_status $status
        if test "$zoom_status" -eq 1
            return 1
        end

        set zoom_initial $zoom_windows

        if test (count $zoom_windows) -eq 0 -a "$zoom_status" -eq 2
            set -l zoom_fallback_info (workspace_app_key_space_fallback_info \
                --app-key zoom \
                --caller $_flag_label \
                --phase zoom_space_fallback \
                --visible)
            set -l zoom_fallback_status $status

            if test "$zoom_fallback_status" -eq 1
                return 1
            end

            if test "$zoom_fallback_status" -eq 2
                if test -n "$_flag_zoom_grid"
                    workspace_apply_app_key_grid_bounds \
                        --app-key zoom \
                        --display $target_display \
                        --grid $_flag_zoom_grid \
                        --caller $_flag_label \
                        --all-windows \
                        --system-events-first >/dev/null 2>&1
                end

                set zoom_fallback_info (workspace_app_key_space_fallback_info \
                    --app-key zoom \
                    --caller $_flag_label \
                    --phase zoom_space_fallback_after_bounds)
                set zoom_fallback_status $status

                if test "$zoom_fallback_status" -eq 0 -a -n "$zoom_fallback_info"
                    set -l zoom_fallback_parts (string split \t -- "$zoom_fallback_info")
                    set zoom_fallback_window $zoom_fallback_parts[1]
                    set zoom_fallback_space $zoom_fallback_parts[2]
                    set zoom_fallback_display $zoom_fallback_parts[3]

                    if test "$zoom_fallback_display" = "$target_display"
                        set zoom_skip_final_bounds_fallback 1
                    else
                        set zoom_fallback_window
                        set zoom_fallback_space
                        set zoom_fallback_display
                    end
                else
                    set zoom_fallback_status 2
                end

                if test -n "$zoom_fallback_space"
                    set -l zoom_fallback_space_windows (ws_query_windows $_flag_label zoom_space_fallback_after_bounds_confirm)
                    if test $status -eq 0
                        set -l confirmed_zoom_display (echo $zoom_fallback_space_windows | ws_jq -r --argjson window "$zoom_fallback_window" '
                            first(.[] | select(.id==$window) | .display) // empty
                        ')

                        if test "$confirmed_zoom_display" != "$target_display"
                            set zoom_fallback_window
                            set zoom_fallback_space
                            set zoom_fallback_display
                            set zoom_skip_final_bounds_fallback 0
                        end
                    end
                end

                if test -z "$zoom_fallback_space"
                    set zoom_status 0
                    set zoom_initial
                    set zoom_windows
                end
            else if test -z "$zoom_fallback_info"
                echo "[WARN] $_flag_label found Zoom, but could not identify a visible Zoom space fallback" >&2
                return 1
            else
                set -l zoom_fallback_parts (string split \t -- "$zoom_fallback_info")
                set zoom_fallback_window $zoom_fallback_parts[1]
                set zoom_fallback_space $zoom_fallback_parts[2]
                set zoom_fallback_display $zoom_fallback_parts[3]

                if test -z "$zoom_fallback_window" -o -z "$zoom_fallback_space" -o -z "$zoom_fallback_display"
                    echo "[WARN] $_flag_label found Zoom, but its fallback space metadata was incomplete" >&2
                    return 1
                end
            end
        end
    end

    set -l teams_space_fallback_used 0
    set -l teams_fallback_window
    set -l teams_fallback_space
    set -l teams_fallback_display

    if test -z "$zoom_fallback_space" -a (count $teams_windows) -eq 0
        set teams_windows (gtd_find_teams_windows $_flag_label --quiet-unmovable)
        set teams_status $status
        if test "$teams_status" -eq 1
            return 1
        end

        set teams_initial $teams_windows

        if test (count $teams_windows) -eq 0 -a "$teams_status" -eq 2
            set -l teams_fallback_info (workspace_app_key_space_fallback_info \
                --app-key teams \
                --caller $_flag_label \
                --phase teams_space_fallback \
                --visible)
            set -l teams_fallback_status $status

            if test "$teams_fallback_status" -eq 1
                return 1
            end

            if test "$teams_fallback_status" -eq 0 -a -n "$teams_fallback_info"
                set -l teams_fallback_parts (string split \t -- "$teams_fallback_info")
                set teams_fallback_window $teams_fallback_parts[1]
                set teams_fallback_space $teams_fallback_parts[2]
                set teams_fallback_display $teams_fallback_parts[3]

                if test -z "$teams_fallback_window" -o -z "$teams_fallback_space" -o -z "$teams_fallback_display"
                    echo "[WARN] $_flag_label found Microsoft Teams, but its fallback space metadata was incomplete" >&2
                    return 1
                end
            end
        end
    end

    if test -z "$zoom_fallback_space" -a -z "$teams_fallback_space"
        set -l teams_unmovable_windows_json (ws_query_windows $_flag_label teams_unmovable_space_fallback)
        or return 1

        set -l teams_unmovable_fallback_info (echo $teams_unmovable_windows_json | ws_jq -r --argjson apps "$teams_apps_json" '
            first(
                .[]
                | select(.app as $app | $apps | index($app))
                | select(.["is-minimized"]==false)
                | select((.["can-move"]!=true) or (.["has-ax-reference"]==false))
                | [.id, .space, .display]
                | @tsv
            ) // empty
        ')
        set -l teams_unmovable_status $status

        if test "$teams_unmovable_status" -ne 0
            return $teams_unmovable_status
        end

        if test -n "$teams_unmovable_fallback_info"
            set -l teams_unmovable_parts (string split \t -- "$teams_unmovable_fallback_info")
            set teams_fallback_window $teams_unmovable_parts[1]
            set teams_fallback_space $teams_unmovable_parts[2]
            set teams_fallback_display $teams_unmovable_parts[3]

            if test -z "$teams_fallback_window" -o -z "$teams_fallback_space" -o -z "$teams_fallback_display"
                echo "[WARN] $_flag_label found Microsoft Teams, but its non-movable companion metadata was incomplete" >&2
                return 1
            end
        end
    end

    if test -z "$zoom_fallback_space" -a -z "$teams_fallback_space" -a "$teams_status" -eq 2 -a (count $zoom_windows) -gt 0
        echo "[WARN] $_flag_label found Microsoft Teams, but could not identify a visible Teams space fallback" >&2
    end

    if test (count $zoom_windows) -eq 0 -a -z "$zoom_fallback_window" -a (count $teams_windows) -eq 0 -a -z "$teams_fallback_window"
        if test "$zoom_status" -eq 2 -o "$teams_status" -eq 2
            return 1
        end

        destroy_empty_labeled_space $_flag_label
        return 0
    end

    set -l target_space

    if test -n "$zoom_fallback_space"
        set zoom_space_fallback_used 1
        set target_space $zoom_fallback_space
        set zoom_windows $zoom_fallback_window

        set target_space (workspace_focus_space_fallback \
            --label $_flag_label \
            --space $target_space \
            --source-display $zoom_fallback_display \
            --target-display $target_display \
            --layout float \
            --phase zoom-space-fallback \
            $cleanup_specs)
        or return 1

        workspace_evict_non_owned_windows_from_space \
            --caller $_flag_label \
            --space $target_space \
            --target-display $target_display \
            --allowed-app-regex (workspace_app_regex zoom teams)
        or return 1
    else if test -n "$teams_fallback_space"
        set teams_space_fallback_used 1
        set target_space $teams_fallback_space
        set teams_windows $teams_fallback_window

        set target_space (workspace_focus_space_fallback \
            --label $_flag_label \
            --space $target_space \
            --source-display $teams_fallback_display \
            --target-display $target_display \
            --layout float \
            --phase teams-space-fallback \
            $cleanup_specs)
        or return 1

        workspace_evict_non_owned_windows_from_space \
            --caller $_flag_label \
            --space $target_space \
            --target-display $target_display \
            --allowed-app-regex (workspace_app_regex zoom teams)
        or return 1
    else
        set target_space (find_or_create_labeled_space $_flag_label $target_display)
        if test -z "$target_space"
            return 1
        end

        set target_space (workspace_retarget_contaminated_space \
            $_flag_label \
            $_flag_label \
            $target_space \
            $target_display \
            (workspace_app_regex zoom teams))
        or return 1

        workspace_focus_labeled_space $_flag_label $target_space $target_display float $cleanup_specs
        or return 1
    end

    if test "$zoom_space_fallback_used" -eq 1
        ws_move_windows_to_space $target_space $teams_windows
    else if test "$teams_space_fallback_used" -eq 1
        ws_move_windows_to_space $target_space $zoom_windows $teams_initial
    else
        ws_move_windows_to_space $target_space $zoom_windows $teams_windows
    end

    set -l windows_json_final (ws_query_windows $_flag_label final)
    or return 1

    if test "$zoom_space_fallback_used" -eq 1
        set zoom_windows (echo $windows_json_final | ws_jq -r --argjson apps "$zoom_apps_json" --argjson s $target_space '
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.space==$s)
            | select(.["is-minimized"]==false)
            | .id
        ')
    else
        set zoom_windows (gtd_find_zoom_windows $_flag_label $target_space --no-refresh --target-only)
    end

    if test "$teams_space_fallback_used" -eq 1
        set teams_windows (echo $windows_json_final | ws_jq -r --argjson apps "$teams_apps_json" --argjson s $target_space '
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.space==$s)
            | select(.["is-minimized"]==false)
            | .id
        ')
    else
        set teams_windows (gtd_find_teams_windows $_flag_label $target_space --no-refresh --target-only)
    end

    if test "$zoom_space_fallback_used" -ne 1
        if test (count $zoom_windows) -eq 0 -a (count $zoom_initial) -gt 0
            ws_move_windows_to_space $target_space $zoom_initial
            set windows_json_final (ws_query_windows $_flag_label final_zoom_retry)
            or return 1
            set zoom_windows (gtd_find_zoom_windows $_flag_label $target_space --no-refresh --target-only)
        end

        if test (count $zoom_windows) -eq 0
            set zoom_windows (gtd_find_zoom_windows $_flag_label --quiet-unmovable)
            if test (count $zoom_windows) -gt 0
                ws_move_windows_to_space $target_space $zoom_windows
                set windows_json_final (ws_query_windows $_flag_label final_zoom_find_retry)
                or return 1
                set zoom_windows (gtd_find_zoom_windows $_flag_label $target_space --no-refresh --target-only)
            end
        end
    end

    if test "$teams_space_fallback_used" -ne 1
        if test (count $teams_windows) -eq 0 -a (count $teams_initial) -gt 0
            ws_move_windows_to_space $target_space $teams_initial
            set windows_json_final (ws_query_windows $_flag_label final_teams_retry)
            or return 1
            set teams_windows (gtd_find_teams_windows $_flag_label $target_space --no-refresh --target-only)
        end

        if test (count $teams_windows) -eq 0
            set teams_windows (gtd_find_teams_windows $_flag_label --no-refresh)
            if test (count $teams_windows) -gt 0
                ws_move_windows_to_space $target_space $teams_windows
                set windows_json_final (ws_query_windows $_flag_label final_teams_find_retry)
                or return 1
                set teams_windows (gtd_find_teams_windows $_flag_label $target_space --no-refresh --target-only)
            end
        end
    end

    workspace_debug_step $_flag_label meeting-window-reconcile

    if test "$zoom_space_fallback_used" -ne 1
        set -l zoom_all_windows (gtd_find_zoom_windows $_flag_label --no-refresh)
        if test $status -eq 1
            return 1
        end

        if test (count $zoom_all_windows) -gt 0
            ws_move_windows_to_space $target_space $zoom_all_windows
            set windows_json_final (ws_query_windows $_flag_label final_zoom_all_reconcile)
            or return 1
            set zoom_windows (gtd_find_zoom_windows $_flag_label $target_space --no-refresh --target-only)
        end
    end

    if test "$teams_space_fallback_used" -ne 1
        set -l teams_all_windows (gtd_find_teams_windows $_flag_label --no-refresh)
        if test $status -eq 1
            return 1
        end

        if test (count $teams_all_windows) -gt 0
            ws_move_windows_to_space $target_space $teams_all_windows
            set windows_json_final (ws_query_windows $_flag_label final_teams_all_reconcile)
            or return 1
            set teams_windows (gtd_find_teams_windows $_flag_label $target_space --no-refresh --target-only)
        end
    end

    sleep 0.35

    if test "$zoom_space_fallback_used" -ne 1
        set -l zoom_settle_windows (gtd_find_zoom_windows $_flag_label --no-refresh)
        if test $status -eq 1
            return 1
        end

        if test (count $zoom_settle_windows) -gt 0
            ws_move_windows_to_space $target_space $zoom_settle_windows
            set windows_json_final (ws_query_windows $_flag_label final_zoom_settle_reconcile)
            or return 1
            set zoom_windows (gtd_find_zoom_windows $_flag_label $target_space --no-refresh --target-only)
        end
    end

    if test "$teams_space_fallback_used" -ne 1
        set -l teams_settle_windows (gtd_find_teams_windows $_flag_label --no-refresh)
        if test $status -eq 1
            return 1
        end

        if test (count $teams_settle_windows) -gt 0
            ws_move_windows_to_space $target_space $teams_settle_windows
            set windows_json_final (ws_query_windows $_flag_label final_teams_settle_reconcile)
            or return 1
            set teams_windows (gtd_find_teams_windows $_flag_label $target_space --no-refresh --target-only)
        end
    end

    if test (count $zoom_windows) -gt 0 -a -n "$_flag_zoom_grid"
        if test "$zoom_space_fallback_used" -eq 1
            if test "$zoom_skip_final_bounds_fallback" -ne 1
                workspace_apply_app_key_grid_bounds \
                    --app-key zoom \
                    --display $target_display \
                    --grid $_flag_zoom_grid \
                    --caller $_flag_label \
                    --all-windows \
                    --system-events-first
            end
        else
            for zoom_window in $zoom_windows
                ws_window $zoom_window --grid $_flag_zoom_grid
            end
        end
    end

    if test (count $teams_windows) -gt 0 -a -n "$_flag_teams_grid"
        if test "$teams_space_fallback_used" -eq 1
            workspace_apply_app_key_grid_bounds \
                --app-key teams \
                --display $target_display \
                --grid $_flag_teams_grid \
                --caller $_flag_label \
                --all-windows \
                --system-events-first
        else
            for teams_window in $teams_windows
                ws_window $teams_window --grid $_flag_teams_grid
            end
        end
    end

    ws_focus_space $target_space

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    cleanup_unlabeled_empty_spaces $target_space
end

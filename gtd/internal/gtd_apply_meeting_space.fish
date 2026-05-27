function gtd_apply_meeting_space --description "Apply a GTD meeting workspace for Outlook, Zoom and Teams"
    argparse \
        'label=' \
        'display=' \
        'outlook-grid=' \
        'zoom-grid=' \
        'teams-grid=' \
        dry-run \
        -- $argv
    or return 1

    if not set -q _flag_label; or not set -q _flag_display
        echo "usage: gtd_apply_meeting_space --label <label> --display <primary|wide|tall> --outlook-grid <grid> --zoom-grid <grid> --teams-grid <grid> [cleanup-spec ...]" >&2
        return 2
    end

    set -l cleanup_specs $argv

    if set -q _flag_dry_run
        set -l teams_apps (string join '|' (workspace_app_names teams))
        printf "dry_run=gtd_apply_meeting_space\n"
        printf "label=%s\n" "$_flag_label"
        printf "display=%s\n" "$_flag_display"
        printf "apps=%s,%s,%s\n" (workspace_app_name outlook) (workspace_app_name zoom) "$teams_apps"
        printf "outlook_grid=%s\n" "$_flag_outlook_grid"
        printf "zoom_grid=%s\n" "$_flag_zoom_grid"
        printf "teams_grid=%s\n" "$_flag_teams_grid"
        printf "cleanup=%s\n" "$cleanup_specs"
        return 0
    end

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    set -l target_display (workspace_resolve_display_role $_flag_display)
    or return $status

    set -l outlook_app (workspace_app_name outlook)

    set -l windows_json (ws_query_windows $_flag_label initial); or return 1
    set -l outlook (echo $windows_json | workspace_select_app_window --app "$outlook_app" --movable)
    set -l outlook_status $status
    set -l zoom (gtd_find_zoom_window $_flag_label --no-refresh)
    set -l teams (gtd_find_teams_window $_flag_label --no-refresh)
    set -l zoom_initial $zoom
    set -l teams_initial $teams

    if test -z "$outlook" -a -z "$zoom" -a -z "$teams"
        if test "$outlook_status" -eq 2
            return 1
        end

        destroy_empty_labeled_space $_flag_label
        return 0
    end

    set -l target_space (find_or_create_labeled_space $_flag_label $target_display)
    if test -z "$target_space"
        return 1
    end

    set target_space (workspace_retarget_contaminated_space \
        $_flag_label \
        $_flag_label \
        $target_space \
        $target_display \
        (workspace_app_regex outlook zoom teams))
    or return 1

    workspace_focus_labeled_space $_flag_label $target_space $target_display float $cleanup_specs
    or return 1

    if test -z "$outlook"
        set outlook (gtd_find_outlook_window $_flag_label $target_space)
        if test $status -eq 2 -a -z "$zoom" -a -z "$teams"
            return 1
        end
    end

    ws_move_windows_to_space $target_space $outlook $zoom $teams

    set -l windows_json_final (ws_query_windows $_flag_label final); or return 1
    set outlook (echo $windows_json_final | ws_find_window "$outlook_app" --space $target_space --movable)

    if test -z "$outlook"
        set outlook (gtd_find_outlook_window $_flag_label $target_space)
        if test -n "$outlook"
            ws_move_windows_to_space $target_space $outlook
            set windows_json_final (ws_query_windows $_flag_label final_outlook_retry); or return 1
            set outlook (echo $windows_json_final | ws_find_window "$outlook_app" --space $target_space --movable)
        end
    end

    set zoom (gtd_find_zoom_window $_flag_label $target_space --no-refresh --target-only)
    set teams (gtd_find_teams_window $_flag_label $target_space --no-refresh --target-only)

    if test -z "$zoom" -a -n "$zoom_initial"
        ws_move_windows_to_space $target_space $zoom_initial
        set windows_json_final (ws_query_windows $_flag_label final_zoom_retry); or return 1
        set zoom (gtd_find_zoom_window $_flag_label $target_space --no-refresh --target-only)
    end

    if test -z "$zoom"
        set zoom (gtd_find_zoom_window $_flag_label --no-refresh)
        if test -n "$zoom"
            ws_move_windows_to_space $target_space $zoom
            set windows_json_final (ws_query_windows $_flag_label final_zoom_find_retry); or return 1
            set zoom (gtd_find_zoom_window $_flag_label $target_space --no-refresh --target-only)
        end
    end

    if test -z "$teams" -a -n "$teams_initial"
        ws_move_windows_to_space $target_space $teams_initial
        set windows_json_final (ws_query_windows $_flag_label final_teams_retry); or return 1
        set teams (gtd_find_teams_window $_flag_label $target_space --no-refresh --target-only)
    end

    if test -z "$teams"
        set teams (gtd_find_teams_window $_flag_label --no-refresh)
        if test -n "$teams"
            ws_move_windows_to_space $target_space $teams
            set windows_json_final (ws_query_windows $_flag_label final_teams_find_retry); or return 1
            set teams (gtd_find_teams_window $_flag_label $target_space --no-refresh --target-only)
        end
    end

    if test -n "$outlook" -a -n "$_flag_outlook_grid"
        ws_window $outlook --grid $_flag_outlook_grid
    end

    if test -n "$zoom" -a -n "$_flag_zoom_grid"
        ws_window $zoom --grid $_flag_zoom_grid
    end

    if test -n "$teams" -a -n "$_flag_teams_grid"
        ws_window $teams --grid $_flag_teams_grid
    end

    ws_focus_space $target_space

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    cleanup_unlabeled_empty_spaces $target_space
end

function gtd_meeting_solo --description "Collect meeting apps onto the solo GTD meeting workspace"
    workspace_debug_step gtd_meeting_solo cleanup
    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces

    set -l label gtd_meeting_solo
    workspace_debug_step gtd_meeting_solo query-initial
    set -l windows_json (ws_query_windows "gtd_meeting_solo" initial); or return 1

    workspace_debug_step gtd_meeting_solo find-outlook-initial
    set -l out (echo $windows_json | workspace_select_app_window --app "Microsoft Outlook" --movable)
    set -l outlook_status $status
    workspace_debug_step gtd_meeting_solo find-outlook-initial-done status=$outlook_status window=$out

    workspace_debug_step gtd_meeting_solo select-zoom-teams
    set -l zoom (gtd_find_zoom_window gtd_meeting_solo --no-refresh)

    set -l teams (gtd_find_teams_window gtd_meeting_solo --no-refresh)
    set -l zoom_initial $zoom
    set -l teams_initial $teams

    if test -z "$out" -a -z "$zoom" -a -z "$teams"
        if test "$outlook_status" -eq 2
            return 1
        end

        destroy_empty_labeled_space $label

        return 0
    end

    workspace_debug_step gtd_meeting_solo resolve-display
    set -l target_display (resolve_internal_display)
    workspace_debug_step gtd_meeting_solo find-or-create-space
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    workspace_debug_step gtd_meeting_solo check-target-space
    set target_space (workspace_retarget_contaminated_space \
        gtd_meeting_solo \
        $label \
        $target_space \
        $target_display \
        '^(Microsoft Outlook|zoom[.]us|Microsoft Teams|MSTeams)$')
    or return 1

    workspace_debug_step gtd_meeting_solo prepare-space
    prepare_labeled_space $target_space $label float

    workspace_debug_step gtd_meeting_solo focus-target
    ws_focus_display $target_display
    sleep 0.15
    ws_focus_space $target_space
    sleep 0.15

    if test -z "$out"
        workspace_debug_step gtd_meeting_solo find-outlook-target
        set out (gtd_find_outlook_window gtd_meeting_solo $target_space)
        if test $status -eq 2 -a -z "$zoom" -a -z "$teams"
            return 1
        end
    else
        workspace_debug_step gtd_meeting_solo reuse-outlook-initial window=$out
    end

    workspace_debug_step gtd_meeting_solo move-windows
    ws_move_windows_to_space $target_space $out $zoom $teams

    workspace_debug_step gtd_meeting_solo query-final
    set -l windows_json_final (ws_query_windows "gtd_meeting_solo" final); or return 1

    workspace_debug_step gtd_meeting_solo select-final
    set out (echo $windows_json_final | ws_find_window "Microsoft Outlook" --space $target_space --movable)

    if test -z "$out"
        workspace_debug_step gtd_meeting_solo fallback-outlook-move
        set out (gtd_find_outlook_window gtd_meeting_solo $target_space)
        if test -n "$out"
            ws_move_windows_to_space $target_space $out
            set windows_json_final (ws_query_windows "gtd_meeting_solo" final); or return 1
            set out (echo $windows_json_final | ws_find_window "Microsoft Outlook" --space $target_space --movable)
        end
    end

    set zoom (gtd_find_zoom_window gtd_meeting_solo $target_space --no-refresh)

    set teams (gtd_find_teams_window gtd_meeting_solo $target_space --no-refresh)

    if test -z "$zoom" -a -n "$zoom_initial"
        workspace_debug_step gtd_meeting_solo fallback-zoom-move
        ws_move_windows_to_space $target_space $zoom_initial
        set windows_json_final (ws_query_windows "gtd_meeting_solo" final_zoom_retry); or return 1
        set zoom (gtd_find_zoom_window gtd_meeting_solo $target_space --no-refresh)
    end

    if test -z "$teams"
        workspace_debug_step gtd_meeting_solo fallback-teams-find
        set teams (gtd_find_teams_window gtd_meeting_solo --no-refresh)
    end

    if test -z "$teams" -a -n "$teams_initial"
        set teams $teams_initial
    end

    if test -n "$teams"
        workspace_debug_step gtd_meeting_solo fallback-teams-move
        ws_move_windows_to_space $target_space $teams
        set windows_json_final (ws_query_windows "gtd_meeting_solo" final_teams_retry); or return 1
        set teams (gtd_find_teams_window gtd_meeting_solo $target_space --no-refresh)
    end

    workspace_debug_step gtd_meeting_solo layout
    if test -n "$zoom"
        ws_window $zoom --grid 2:3:0:0:1:1
    end

    if test -n "$teams"
        ws_window $teams --grid 2:3:0:1:1:1
    end

    if test -n "$out"
        ws_window $out --grid 2:3:1:0:2:2
    end

    workspace_debug_step gtd_meeting_solo cleanup-final
    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

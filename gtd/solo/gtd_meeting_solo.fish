function gtd_meeting_solo --description "Collect meeting apps onto the solo GTD meeting workspace"
    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces

    set -l label gtd_meeting_solo
    set -l windows_json (ws_query_windows "gtd_meeting_solo" initial); or return 1

    set -l out (echo $windows_json | ws_find_window "Microsoft Outlook")

    set -l zoom (echo $windows_json | ws_find_window "zoom.us")

    set -l teams (echo $windows_json | ws_find_window "Microsoft Teams")

    if test -z "$out" -a -z "$zoom" -a -z "$teams"
        destroy_empty_labeled_space $label

        return 0
    end

    set -l target_display (resolve_internal_display)
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    ws_focus_space $target_space
    sleep 0.15

    ws_move_windows_to_space $target_space $out $zoom $teams

    set -l windows_json_final (ws_query_windows "gtd_meeting_solo" final); or return 1

    set out (echo $windows_json_final | ws_find_window "Microsoft Outlook" --space $target_space)

    set zoom (echo $windows_json_final | ws_find_window "zoom.us" --space $target_space)

    set teams (echo $windows_json_final | ws_find_window "Microsoft Teams" --space $target_space)

    if test -n "$zoom"
        ws_window $zoom --grid 2:2:0:0:1:1
    end

    if test -n "$teams"
        ws_window $teams --grid 2:2:0:1:1:1
    end

    if test -n "$out"
        ws_window $out --grid 1:2:1:0:1:1
    end

    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

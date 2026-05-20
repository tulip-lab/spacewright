function gtd_support_solo --description "Collect Dia onto the solo GTD support workspace"
    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces

    set -l label gtd_support_solo
    set -l windows_json (ws_query_windows "gtd_support_solo" initial); or return 1

    set -l dia_windows (printf '%s\n' "$windows_json" | gtd_support_find_dia_windows gtd_support_solo)
    or return 1

    if test (count $dia_windows) -eq 0
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

    ws_move_windows_to_space $target_space $dia_windows

    set -l windows_json_final (ws_query_windows "gtd_support_solo" final); or return 1

    set dia_windows (printf '%s\n' "$windows_json_final" | ws_find_windows "Dia" --space $target_space)
    gtd_support_layout_dia_windows solo $dia_windows

    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

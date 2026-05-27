function gtd_support_solo --description "Collect Dia onto the solo GTD support workspace"
    workspace_cleanup_mode_spaces gtd wide
    workspace_cleanup_mode_spaces gtd tall
    set -l label gtd_support_solo
    set -l windows_json (ws_query_windows "gtd_support_solo" initial); or return 1

    set -l dia_windows (printf '%s\n' "$windows_json" | gtd_support_find_dia_windows gtd_support_solo)
    or return 1

    if test (count $dia_windows) -eq 0
        destroy_empty_labeled_space $label

        return 0
    end

    set -l target_display (resolve_workspace_primary_display)
    set -l target_space (workspace_prepare_labeled_space $label $target_display float)
    or return 1

    ws_move_windows_to_space $target_space $dia_windows

    set -l windows_json_final (ws_query_windows "gtd_support_solo" final); or return 1

    set dia_windows (printf '%s\n' "$windows_json_final" | ws_find_windows "Dia" --space $target_space)
    gtd_support_layout_dia_windows solo $dia_windows

    workspace_cleanup_mode_spaces gtd wide
    workspace_cleanup_mode_spaces gtd tall
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

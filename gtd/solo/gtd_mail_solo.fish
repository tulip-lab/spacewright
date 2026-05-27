function gtd_mail_solo --description "Collect Thunderbird onto the solo GTD mail workspace"
    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces

    set -l label gtd_mail_solo
    set -l windows_json (ws_query_windows "gtd_mail_solo" initial); or return 1

    set -l tb (echo $windows_json | ws_find_window "Thunderbird")

    if test -z "$tb"
        destroy_empty_labeled_space $label

        return 0
    end

    set -l target_display (resolve_workspace_primary_display)
    set -l target_space (workspace_prepare_labeled_space $label $target_display float)
    or return 1

    ws_move_app_to_space $target_space "Thunderbird" $tb

    set -l windows_json_final (ws_query_windows "gtd_mail_solo" final); or return 1

    set tb (echo $windows_json_final | ws_find_window "Thunderbird" --space $target_space)

    if test -n "$tb"
        ws_window $tb --grid 1:1:0:0:1:1
    end

    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

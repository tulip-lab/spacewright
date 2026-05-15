function gtd_mail_solo --description "Collect Thunderbird onto the solo GTD mail workspace"
    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces

    set -l label gtd_mail_solo
    set -l windows_json (yabai -m query --windows)

    set -l tb (echo $windows_json | ws_find_window "Thunderbird")

    if test -z "$tb"
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

    ws_move_app_to_space $target_space "Thunderbird" $tb

    set -l windows_json_final (yabai -m query --windows)

    set tb (echo $windows_json_final | ws_find_window "Thunderbird" --space $target_space)

    if test -n "$tb"
        ws_window $tb --grid 1:1:0:0:1:1
    end

    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

function gtd_review_solo --description "Collect review-related windows onto the solo GTD review workspace"
    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces

    set -l label gtd_review_solo
    set -l windows_json (ws_query_windows "gtd_review_solo" initial); or return 1

    set -l preview (echo $windows_json | ws_find_window "Preview")
    set -l chatgpt_initial (echo $windows_json | ws_find_window "ChatGPT")
    set -l notes (echo $windows_json | ws_find_window "Notes" --nonempty-title)

    if test -z "$notes"
        set notes (echo $windows_json | ws_find_window "Notes")
    end

    if test -z "$preview" -a -z "$notes" -a -z "$chatgpt_initial"
        destroy_empty_labeled_space $label

        return 0
    end

    set -l finder (echo $windows_json | ws_find_window "Finder")

    set -l target_display (resolve_internal_display)
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    set target_space (workspace_retarget_contaminated_space \
        gtd_review_solo \
        $label \
        $target_space \
        $target_display \
        '^(Finder|Preview|ChatGPT|Notes)$')
    or return 1

    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    ws_focus_space $target_space
    sleep 0.15

    ws_move_windows_to_space $target_space $finder $preview $notes
    set -l chatgpt (workspace_capture_app_window --app ChatGPT --caller gtd_review_solo --space $target_space)

    set -l windows_json_final (ws_query_windows "gtd_review_solo" final); or return 1

    set finder (echo $windows_json_final | ws_find_window "Finder" --space $target_space)

    set preview (echo $windows_json_final | ws_find_window "Preview" --space $target_space)

    set chatgpt (workspace_find_app_window --app ChatGPT --caller gtd_review_solo --space $target_space --no-refresh)

    set notes (echo $windows_json_final | ws_find_window "Notes" --space $target_space --nonempty-title)

    if test -z "$notes"
        set notes (echo $windows_json_final | ws_find_window "Notes" --space $target_space)
    end

    if test -n "$finder"
        ws_window $finder --grid 2:3:0:0:1:1
    end

    if test -n "$preview"
        ws_window $preview --grid 2:3:1:0:2:1
    end

    if test -n "$chatgpt"
        ws_window $chatgpt --grid 2:2:0:1:1:1
    end

    if test -n "$notes"
        ws_window $notes --grid 2:2:1:1:1:1
    end

    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

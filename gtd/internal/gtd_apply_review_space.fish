function gtd_apply_review_space --description "Apply a GTD review workspace for Finder, Preview, ChatGPT and Notes"
    argparse \
        'label=' \
        'display=' \
        'finder-grid=' \
        'preview-grid=' \
        'chatgpt-grid=' \
        'notes-grid=' \
        dry-run \
        -- $argv
    or return 1

    if not set -q _flag_label; or not set -q _flag_display
        echo "usage: gtd_apply_review_space --label <label> --display <primary|wide|tall> [grid options] [cleanup-spec ...]" >&2
        return 2
    end

    set -l cleanup_specs $argv

    if set -q _flag_dry_run
        printf "dry_run=gtd_apply_review_space\n"
        printf "label=%s\n" "$_flag_label"
        printf "display=%s\n" "$_flag_display"
        printf "apps=%s,%s,%s,%s\n" (workspace_app_name finder) (workspace_app_name preview) (workspace_app_name chatgpt) (workspace_app_name notes)
        printf "finder_grid=%s\n" "$_flag_finder_grid"
        printf "preview_grid=%s\n" "$_flag_preview_grid"
        printf "chatgpt_grid=%s\n" "$_flag_chatgpt_grid"
        printf "notes_grid=%s\n" "$_flag_notes_grid"
        printf "cleanup=%s\n" "$cleanup_specs"
        return 0
    end

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    set -l windows_json (ws_query_windows $_flag_label initial); or return 1
    set -l finder_app (workspace_app_name finder)
    set -l preview_app (workspace_app_name preview)
    set -l chatgpt_app (workspace_app_name chatgpt)
    set -l notes_app (workspace_app_name notes)

    set -l preview (echo $windows_json | ws_find_window "$preview_app")
    set -l chatgpt_initial (echo $windows_json | ws_find_window "$chatgpt_app")
    set -l notes (echo $windows_json | ws_find_window "$notes_app" --nonempty-title)

    if test -z "$notes"
        set notes (echo $windows_json | ws_find_window "$notes_app")
    end

    if test -z "$preview" -a -z "$notes" -a -z "$chatgpt_initial"
        destroy_empty_labeled_space $_flag_label
        return 0
    end

    set -l finder (echo $windows_json | ws_find_window "$finder_app")
    set -l target_display (workspace_resolve_display_role $_flag_display)
    or return $status

    set -l target_space (find_or_create_labeled_space $_flag_label $target_display)
    if test -z "$target_space"
        return 1
    end

    set target_space (workspace_retarget_contaminated_space \
        $_flag_label \
        $_flag_label \
        $target_space \
        $target_display \
        (workspace_app_regex finder preview chatgpt notes))
    or return 1

    workspace_focus_labeled_space $_flag_label $target_space $target_display float $cleanup_specs
    or return 1

    ws_move_windows_to_space $target_space $finder $preview $notes
    set -l chatgpt (workspace_capture_app_window --app "$chatgpt_app" --caller $_flag_label --space $target_space)

    set -l windows_json_final (ws_query_windows $_flag_label final); or return 1
    set finder (echo $windows_json_final | ws_find_window "$finder_app" --space $target_space)
    set preview (echo $windows_json_final | ws_find_window "$preview_app" --space $target_space)
    set chatgpt (workspace_find_app_window --app "$chatgpt_app" --caller $_flag_label --space $target_space --no-refresh)
    set notes (echo $windows_json_final | ws_find_window "$notes_app" --space $target_space --nonempty-title)

    if test -z "$notes"
        set notes (echo $windows_json_final | ws_find_window "$notes_app" --space $target_space)
    end

    if test -n "$finder" -a -n "$_flag_finder_grid"
        ws_window $finder --grid $_flag_finder_grid
    end

    if test -n "$preview" -a -n "$_flag_preview_grid"
        ws_window $preview --grid $_flag_preview_grid
    end

    if test -n "$chatgpt" -a -n "$_flag_chatgpt_grid"
        ws_window $chatgpt --grid $_flag_chatgpt_grid
    end

    if test -n "$notes" -a -n "$_flag_notes_grid"
        ws_window $notes --grid $_flag_notes_grid
    end

    ws_focus_space $target_space

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    cleanup_unlabeled_empty_spaces $target_space
end

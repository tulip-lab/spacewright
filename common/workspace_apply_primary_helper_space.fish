function workspace_apply_primary_helper_space --description "Apply a labeled workspace with one required primary app and one optional helper app"
    argparse \
        'label=' \
        'caller=' \
        'display=' \
        'layout=' \
        'primary-app=' \
        'primary-app-key=' \
        'helper-app=' \
        'helper-app-key=' \
        'primary-grid=' \
        'primary-alone-grid=' \
        'helper-grid=' \
        helper-visible \
        dry-run \
        -- $argv
    or return 1

    if set -q _flag_primary_app_key
        set _flag_primary_app (workspace_app_name $_flag_primary_app_key)
        or return 1
    end

    if set -q _flag_helper_app_key
        set _flag_helper_app (workspace_app_name $_flag_helper_app_key)
        or return 1
    end

    if not set -q _flag_label; or not set -q _flag_display; or not set -q _flag_primary_app; or not set -q _flag_primary_grid
        echo "usage: workspace_apply_primary_helper_space --label <label> --display <primary|wide|tall> --primary-app <app>|--primary-app-key <key> --primary-grid <grid> [--helper-app <app>|--helper-app-key <key> --helper-grid <grid>] [--dry-run] [cleanup-spec ...]" >&2
        return 2
    end

    set -l label $_flag_label
    set -l caller $label
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l layout float
    if set -q _flag_layout
        set layout $_flag_layout
    end

    set -l cleanup_specs $argv

    if set -q _flag_dry_run
        printf "dry_run=workspace_apply_primary_helper_space\n"
        printf "label=%s\n" "$label"
        printf "display=%s\n" "$_flag_display"
        printf "layout=%s\n" "$layout"
        printf "primary_app=%s\n" "$_flag_primary_app"
        if set -q _flag_helper_app
            printf "helper_app=%s\n" "$_flag_helper_app"
        end
        printf "primary_grid=%s\n" "$_flag_primary_grid"
        if set -q _flag_primary_alone_grid
            printf "primary_alone_grid=%s\n" "$_flag_primary_alone_grid"
        end
        if set -q _flag_helper_grid
            printf "helper_grid=%s\n" "$_flag_helper_grid"
        end
        printf "cleanup=%s\n" "$cleanup_specs"
        return 0
    end

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    set -l windows_json (ws_query_windows $caller initial); or return 1
    set -l primary_window (echo $windows_json | ws_find_window "$_flag_primary_app")

    if test -z "$primary_window"
        destroy_empty_labeled_space $label
        return 0
    end

    set -l target_display (workspace_resolve_display_role $_flag_display)
    or return $status

    set -l target_space (workspace_prepare_labeled_space $label $target_display $layout $cleanup_specs)
    or return 1

    ws_move_windows_to_space $target_space $primary_window

    set -l helper_window
    if set -q _flag_helper_app
        set -l helper_find_args --app "$_flag_helper_app" --caller $caller --space $target_space
        if set -q _flag_helper_visible
            set -a helper_find_args --visible
        end

        set helper_window (workspace_capture_app_window $helper_find_args)
    end

    set -l windows_json_final (ws_query_windows $caller final); or return 1
    set primary_window (echo $windows_json_final | ws_find_window "$_flag_primary_app" --space $target_space)

    if set -q _flag_helper_app
        set -l final_helper_args --app "$_flag_helper_app" --caller $caller --space $target_space --no-refresh
        if set -q _flag_helper_visible
            set -a final_helper_args --visible
        end

        set helper_window (workspace_find_app_window $final_helper_args)
    end

    if test -n "$helper_window" -a -n "$_flag_helper_grid"
        ws_window $helper_window --grid $_flag_helper_grid
    end

    if test -n "$primary_window"
        set -l primary_grid $_flag_primary_grid
        if test -z "$helper_window"; and set -q _flag_primary_alone_grid
            set primary_grid $_flag_primary_alone_grid
        end

        ws_window $primary_window --grid $primary_grid
    end

    ws_focus_space $target_space

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    cleanup_unlabeled_empty_spaces $target_space
end

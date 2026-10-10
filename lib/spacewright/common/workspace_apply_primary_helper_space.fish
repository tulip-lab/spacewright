function workspace_apply_primary_helper_space --description "Apply a labeled workspace with one required primary app and one optional helper app"
    argparse \
        'label=' \
        'caller=' \
        'display=' \
        'layout=' \
        'primary-app=' \
        'primary-app-key=' \
        'primary-window=' \
        'helper-app=' \
        'helper-app-key=' \
        'primary-grid=' \
        'primary-alone-grid=' \
        'helper-grid=' \
        primary-space-fallback \
        helper-space-fallback \
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
        echo "usage: workspace_apply_primary_helper_space --label <label> --display <primary|wide|tall> --primary-app <app>|--primary-app-key <key> --primary-grid <grid> [--primary-space-fallback] [--helper-app <app>|--helper-app-key <key> --helper-grid <grid>] [--dry-run] [cleanup-spec ...]" >&2
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
        if set -q _flag_primary_space_fallback
            printf "primary_space_fallback=%s\n" true
        end
        if set -q _flag_helper_space_fallback
            printf "helper_space_fallback=%s\n" true
        end
        printf "cleanup=%s\n" "$cleanup_specs"
        return 0
    end

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    set -l primary_space_fallback_used 0
    set -l helper_space_fallback_used 0
    set -l helper_fallback_window
    set -l target_display
    set -l target_space

    set -l primary_find_args --caller $caller
    if set -q _flag_primary_space_fallback
        set -a primary_find_args --quiet-unmovable
    end
    if set -q _flag_primary_app_key
        set -a primary_find_args --app-key $_flag_primary_app_key
    else
        set -a primary_find_args --app "$_flag_primary_app"
    end

    set -l primary_window
    set -l primary_find_status 0
    if set -q _flag_primary_window
        if not string match -qr '^[0-9]+$' -- "$_flag_primary_window"
            echo "[WARN] $caller received an invalid preselected primary window id" >&2
            return 2
        end
        set primary_window $_flag_primary_window
    else
        if set -q _flag_primary_app_key
            set primary_window (workspace_find_app_key_window $primary_find_args)
        else
            set primary_window (workspace_find_app_window $primary_find_args)
        end
        set primary_find_status $status
    end

    if test "$primary_find_status" -eq 1
        return 1
    end

    if test -z "$primary_window"
        if test "$primary_find_status" -eq 2
            if set -q _flag_primary_space_fallback; and set -q _flag_primary_app_key
                set target_display (workspace_resolve_display_role $_flag_display)
                or return $status

                set -l primary_fallback_info (workspace_app_key_space_fallback_info \
                    --app-key $_flag_primary_app_key \
                    --caller $caller \
                    --phase primary_space_fallback)
                set -l primary_fallback_status $status

                if test "$primary_fallback_status" -eq 1
                    return 1
                end

                if test -z "$primary_fallback_info"
                    return 1
                end

                set -l primary_fallback_parts (string split \t -- "$primary_fallback_info")
                set primary_window $primary_fallback_parts[1]
                set target_space $primary_fallback_parts[2]
                set -l source_display $primary_fallback_parts[3]

                if test -z "$primary_window" -o -z "$target_space" -o -z "$source_display"
                    return 1
                end

                set target_space (workspace_focus_space_fallback \
                    --label $label \
                    --caller $caller \
                    --space $target_space \
                    --source-display $source_display \
                    --target-display $target_display \
                    --layout $layout \
                    --phase primary-space-fallback \
                    $cleanup_specs)
                or return 1

                set -l primary_fallback_allowed_app_regex (workspace_app_regex $_flag_primary_app_key)
                or return 1
                if set -q _flag_helper_app_key
                    set primary_fallback_allowed_app_regex (workspace_app_regex $_flag_primary_app_key $_flag_helper_app_key)
                    or return 1
                end

                workspace_evict_non_owned_windows_from_space \
                    --caller $caller \
                    --space $target_space \
                    --target-display $target_display \
                    --allowed-app-regex "$primary_fallback_allowed_app_regex"
                or return 1

                set primary_space_fallback_used 1
            else
                return 1
            end
        end

        if test -z "$primary_window"
            destroy_empty_labeled_space $label
            return 0
        end
    end

    if test "$primary_space_fallback_used" -ne 1
        set target_display (workspace_resolve_display_role $_flag_display)
        or return $status

        if set -q _flag_helper_space_fallback; and set -q _flag_primary_app_key; and set -q _flag_helper_app_key
            set -l helper_probe (workspace_find_app_key_window \
                --app-key $_flag_helper_app_key \
                --caller $caller \
                --quiet-unmovable \
                --attempts 1 \
                --wait 0.2)
            set -l helper_probe_status $status

            if test "$helper_probe_status" -eq 1
                return 1
            end

            if test -z "$helper_probe" -a "$helper_probe_status" -eq 2
                set -l helper_fallback_info (workspace_app_key_space_fallback_info \
                    --app-key $_flag_helper_app_key \
                    --caller $caller \
                    --phase helper_space_fallback)
                set -l helper_fallback_status $status

                if test "$helper_fallback_status" -eq 1
                    return 1
                end

                if test -n "$helper_fallback_info"
                    set -l helper_fallback_parts (string split \t -- "$helper_fallback_info")
                    set helper_fallback_window $helper_fallback_parts[1]
                    set target_space $helper_fallback_parts[2]
                    set -l helper_source_display $helper_fallback_parts[3]

                    if test -z "$helper_fallback_window" -o -z "$target_space" -o -z "$helper_source_display"
                        return 1
                    end

                    set target_space (workspace_focus_space_fallback \
                        --label $label \
                        --caller $caller \
                        --space $target_space \
                        --source-display $helper_source_display \
                        --target-display $target_display \
                        --layout $layout \
                        --phase helper-space-fallback \
                        $cleanup_specs)
                    or return 1

                    set -l helper_fallback_allowed_app_regex (workspace_app_regex $_flag_primary_app_key $_flag_helper_app_key)
                    or return 1

                    workspace_evict_non_owned_windows_from_space \
                        --caller $caller \
                        --space $target_space \
                        --target-display $target_display \
                        --allowed-app-regex "$helper_fallback_allowed_app_regex"
                    or return 1

                    ws_move_windows_to_space $target_space $primary_window
                    set helper_space_fallback_used 1
                end
            end
        end

        if test "$helper_space_fallback_used" -ne 1
            set target_space (workspace_prepare_labeled_space $label $target_display $layout $cleanup_specs)
            or return 1

            ws_move_windows_to_space $target_space $primary_window
        end
    end

    set -l primary_target_find_args $primary_find_args --space $target_space --no-refresh --target-only

    if set -q _flag_primary_app_key
        set primary_window (workspace_find_app_key_window $primary_target_find_args)
    else
        set primary_window (workspace_find_app_window $primary_target_find_args)
    end

    if test -z "$primary_window" -a "$primary_space_fallback_used" -ne 1
        workspace_debug_step $caller primary-move-missing "$_flag_primary_app" target_space=$target_space

        if set -q _flag_primary_app_key
            set primary_window (workspace_find_app_key_window $primary_find_args)
        else
            set primary_window (workspace_find_app_window $primary_find_args)
        end
        set primary_find_status $status

        if test "$primary_find_status" -eq 1
            return 1
        end

        if test -n "$primary_window"
            ws_move_windows_to_space $target_space $primary_window

            if set -q _flag_primary_app_key
                set primary_window (workspace_find_app_key_window $primary_target_find_args)
            else
                set primary_window (workspace_find_app_window $primary_target_find_args)
            end
        end

        if test -z "$primary_window"
            echo "[WARN] $caller could not move $_flag_primary_app to space $target_space" >&2
            return 1
        end
    end

    set -l helper_window
    if set -q _flag_helper_app
        if test "$helper_space_fallback_used" -eq 1
            set helper_window $helper_fallback_window
        else
            set -l helper_find_args --caller $caller --space $target_space
            if set -q _flag_helper_app_key
                set -a helper_find_args --app-key $_flag_helper_app_key
            else
                set -a helper_find_args --app "$_flag_helper_app"
            end

            if set -q _flag_helper_visible
                set -a helper_find_args --visible
            end

            set helper_window (workspace_capture_app_window $helper_find_args)
            set -l helper_capture_status $status
            if test "$helper_capture_status" -eq 1
                return 1
            end
            if test "$helper_capture_status" -eq 2
                workspace_debug_step $caller helper-capture-retry "$_flag_helper_app"
                sleep 0.6
                set helper_window (workspace_capture_app_window $helper_find_args)
                set helper_capture_status $status
                if test "$helper_capture_status" -eq 1
                    return 1
                end
                if test "$helper_capture_status" -eq 2
                    echo "[WARN] $caller found $_flag_helper_app but could not settle it on Space $target_space" >&2
                end
            end
        end
    end

    set -l windows_json_final (ws_query_windows $caller final); or return 1
    if test "$primary_space_fallback_used" -eq 1
        set -l primary_apps_json (workspace_app_names_json $_flag_primary_app_key)
        or return 1

        set primary_window (echo $windows_json_final | ws_jq -r --argjson apps "$primary_apps_json" --argjson s $target_space '
            first(
                .[]
                | select(.app as $app | $apps | index($app))
                | select(.space==$s)
                | select(.["is-minimized"]==false)
                | .id
            ) // empty
        ')
    else if set -q _flag_primary_app_key
        set -l primary_target_windows (echo $windows_json_final | workspace_app_key_windows \
            --app-key $_flag_primary_app_key \
            --space $target_space \
            --movable)
        or return 1
        set primary_window $primary_target_windows[1]
    else
        set primary_window (echo $windows_json_final | ws_find_window "$_flag_primary_app" --space $target_space)
    end

    if set -q _flag_helper_app
        if test "$helper_space_fallback_used" -eq 1; and set -q _flag_helper_app_key
            set -l helper_target_windows (echo $windows_json_final | workspace_app_key_windows --app-key $_flag_helper_app_key --space $target_space)
            or return 1
            set helper_window $helper_target_windows[1]
            if test -z "$helper_window"
                set helper_window $helper_fallback_window
            end
        else if set -q _flag_helper_app_key
            set -l helper_target_args --app-key $_flag_helper_app_key --space $target_space --movable
            if set -q _flag_helper_visible
                set -a helper_target_args --visible
            end
            set -l helper_target_windows (echo $windows_json_final | workspace_app_key_windows $helper_target_args)
            or return 1
            set helper_window $helper_target_windows[1]
        else
            set -l final_helper_args --caller $caller --space $target_space --no-refresh --target-only
            set -a final_helper_args --app "$_flag_helper_app"

            if set -q _flag_helper_visible
                set -a final_helper_args --visible
            end

            set helper_window (workspace_find_app_window $final_helper_args)
        end
    end

    if test -n "$helper_window" -a -n "$_flag_helper_grid"
        if test "$helper_space_fallback_used" -eq 1; and set -q _flag_helper_app_key
            workspace_apply_app_key_grid_bounds \
                --app-key $_flag_helper_app_key \
                --display $target_display \
                --grid $_flag_helper_grid \
                --caller $caller
        else
            ws_window $helper_window --grid $_flag_helper_grid
        end
    end

    if test -n "$primary_window"
        set -l primary_grid $_flag_primary_grid
        if test -z "$helper_window"; and set -q _flag_primary_alone_grid
            set primary_grid $_flag_primary_alone_grid
        end

        if test "$primary_space_fallback_used" -eq 1
            workspace_apply_app_key_grid_bounds \
                --app-key $_flag_primary_app_key \
                --display $target_display \
                --grid $primary_grid \
                --caller $caller
        else
            ws_window $primary_window --grid $primary_grid
        end
    end

    ws_focus_space $target_space

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    cleanup_unlabeled_empty_spaces $target_space
end

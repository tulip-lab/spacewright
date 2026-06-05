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
    set -l chatgpt_app (workspace_app_name chatgpt)
    set -l preview_apps_json (workspace_app_names_json preview)
    or return 1
    set -l notes_apps_json (workspace_app_names_json notes)
    or return 1

    set -l finder_windows (echo $windows_json | workspace_app_key_windows --app-key finder --movable)
    or return 1

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l preview
    set -l preview_movable_windows (echo $windows_json | workspace_app_key_windows --app-key preview --movable)
    or return 1
    set -l preview_fallback_window
    set -l preview_fallback_space
    set -l preview_fallback_display

    for preview_window in $preview_movable_windows
        rm -f "$bad_window_dir/$preview_window" 2>/dev/null
    end

    if test (count $preview_movable_windows) -gt 0
        set preview $preview_movable_windows[1]
    end

    set -l preview_initial_info (echo $windows_json | workspace_app_key_window_info --app-key preview --unmovable)
    if test $status -ne 0
        return 1
    end

    if test -z "$preview"
        if test -n "$preview_initial_info"
            set -l preview_initial_parts (string split \t -- "$preview_initial_info")
            set preview_fallback_window $preview_initial_parts[1]
            set preview_fallback_space $preview_initial_parts[2]
            set preview_fallback_display $preview_initial_parts[3]
        else
            set preview (workspace_find_app_key_window --app-key preview --caller $_flag_label --quiet-unmovable)
            set -l preview_status $status
            if test "$preview_status" -eq 1
                return 1
            end

            if test "$preview_status" -eq 2
                set -l preview_fallback_info (workspace_app_key_space_fallback_info \
                    --app-key preview \
                    --caller $_flag_label \
                    --phase preview_space_fallback)
                set -l preview_fallback_status $status

                if test "$preview_fallback_status" -eq 1
                    return 1
                end

                if test -z "$preview_fallback_info"
                    echo "[WARN] $_flag_label found Preview, but could not identify a Preview space fallback" >&2
                    return 1
                end

                set -l preview_fallback_parts (string split \t -- "$preview_fallback_info")
                set preview_fallback_window $preview_fallback_parts[1]
                set preview_fallback_space $preview_fallback_parts[2]
                set preview_fallback_display $preview_fallback_parts[3]
            end
        end
    end

    if test -n "$preview_fallback_window"
        if test -z "$preview_fallback_window" -o -z "$preview_fallback_space" -o -z "$preview_fallback_display"
            echo "[WARN] $_flag_label found Preview, but its fallback space metadata was incomplete" >&2
            return 1
        end
    end

    set -l chatgpt_initial_info (echo $windows_json | workspace_app_key_window_info --app-key chatgpt)
    if test $status -ne 0
        return 1
    end

    set -l chatgpt_movable_windows (echo $windows_json | workspace_app_key_windows --app-key chatgpt --movable)
    or return 1

    set -l notes
    set -l notes_status 0
    set -l notes_movable_windows (echo $windows_json | workspace_app_key_windows --app-key notes --movable)
    or return 1

    set -l notes_space_fallback_used 0
    set -l notes_fallback_window
    set -l notes_fallback_space
    set -l notes_fallback_display

    for notes_window in $notes_movable_windows
        rm -f /tmp/workspace-ws-window-bad/$notes_window 2>/dev/null
    end

    if test (count $notes_movable_windows) -gt 0
        set notes $notes_movable_windows[1]
    else
        set -l notes_initial_info (echo $windows_json | workspace_app_key_window_info --app-key notes --unmovable)
        if test $status -ne 0
            return 1
        end

        if test -n "$notes_initial_info"
            set -l notes_initial_parts (string split \t -- "$notes_initial_info")
            set notes_status 2
            set notes_fallback_window $notes_initial_parts[1]
            set notes_fallback_space $notes_initial_parts[2]
            set notes_fallback_display $notes_initial_parts[3]
        end
    end

    if test -z "$notes" -a "$notes_status" -eq 2 -a -z "$notes_fallback_window"
        set -l notes_fallback_info (workspace_app_key_space_fallback_info \
            --app-key notes \
            --caller $_flag_label \
            --phase notes_space_fallback)
        set -l notes_fallback_status $status

        if test "$notes_fallback_status" -eq 1
            return 1
        end

        if test -z "$notes_fallback_info"
            echo "[WARN] $_flag_label found Notes, but could not identify a Notes space fallback" >&2
            return 1
        end

        set -l notes_fallback_parts (string split \t -- "$notes_fallback_info")
        set notes_fallback_window $notes_fallback_parts[1]
        set notes_fallback_space $notes_fallback_parts[2]
        set notes_fallback_display $notes_fallback_parts[3]

        if test -z "$notes_fallback_window" -o -z "$notes_fallback_space" -o -z "$notes_fallback_display"
            echo "[WARN] $_flag_label found Notes, but its fallback space metadata was incomplete" >&2
            return 1
        end
    end

    if test -z "$preview" -a -z "$preview_fallback_window" -a -z "$notes" -a -z "$notes_fallback_window" -a -z "$chatgpt_initial_info"
        destroy_empty_labeled_space $_flag_label
        return 0
    end

    set -l target_display (workspace_resolve_display_role $_flag_display)
    or return $status
    set -l review_app_regex (workspace_app_regex finder preview chatgpt notes)
    or return 1

    set -l target_space

    if test -n "$notes_fallback_space"
        set notes_space_fallback_used 1
        set target_space $notes_fallback_space
        set notes $notes_fallback_window

        set target_space (workspace_focus_space_fallback \
            --label $_flag_label \
            --space $target_space \
            --source-display $notes_fallback_display \
            --target-display $target_display \
            --layout float \
            --phase notes-space-fallback \
            $cleanup_specs)
        or return 1

        workspace_evict_non_owned_windows_from_space \
            --caller $_flag_label \
            --space $target_space \
            --target-display $target_display \
            --allowed-app-regex "$review_app_regex"
        or return 1
    else if test -n "$preview_fallback_space"
        set target_space $preview_fallback_space
        set preview $preview_fallback_window

        set target_space (workspace_focus_space_fallback \
            --label $_flag_label \
            --space $target_space \
            --source-display $preview_fallback_display \
            --target-display $target_display \
            --layout float \
            --phase preview-space-fallback \
            $cleanup_specs)
        or return 1

        workspace_evict_non_owned_windows_from_space \
            --caller $_flag_label \
            --space $target_space \
            --target-display $target_display \
            --allowed-app-regex "$review_app_regex"
        or return 1
    else
        set target_space (find_or_create_labeled_space $_flag_label $target_display)
        if test -z "$target_space"
            return 1
        end

        set target_space (workspace_retarget_contaminated_space \
            $_flag_label \
            $_flag_label \
            $target_space \
            $target_display \
            "$review_app_regex")
        or return 1

        workspace_focus_labeled_space $_flag_label $target_space $target_display float
        or return 1
    end

    set -l finder_move_windows (echo $windows_json | workspace_app_key_windows --app-key finder --movable --not-space $target_space)
    or return 1
    set -l preview_move_windows (echo $windows_json | workspace_app_key_windows --app-key preview --movable --not-space $target_space)
    or return 1
    set -l chatgpt_move_windows (echo $windows_json | workspace_app_key_windows --app-key chatgpt --movable --not-space $target_space)
    or return 1

    set -l windows_to_move $finder_move_windows $preview_move_windows $chatgpt_move_windows

    if test "$notes_space_fallback_used" -ne 1
        set -l notes_move_windows (echo $windows_json | workspace_app_key_windows --app-key notes --movable --not-space $target_space)
        or return 1
        set -a windows_to_move $notes_move_windows
    end

    if test (count $windows_to_move) -gt 0
        ws_move_windows_to_space $target_space $windows_to_move
    end

    set -l windows_json_final (ws_query_windows $_flag_label final); or return 1

    for attempt in (seq 1 3)
        set -l finder_retry_windows (echo $windows_json_final | workspace_app_key_windows --app-key finder --movable --not-space $target_space)
        or return 1
        set -l preview_retry_windows (echo $windows_json_final | workspace_app_key_windows --app-key preview --movable --not-space $target_space)
        or return 1
        set -l notes_retry_windows
        if test "$notes_space_fallback_used" -ne 1
            set notes_retry_windows (echo $windows_json_final | workspace_app_key_windows --app-key notes --movable --not-space $target_space)
            or return 1
        end

        for preview_window in $preview_retry_windows
            rm -f "$bad_window_dir/$preview_window" 2>/dev/null
        end

        for notes_window in $notes_retry_windows
            rm -f "$bad_window_dir/$notes_window" 2>/dev/null
        end

        if test (count $finder_retry_windows) -eq 0; and test (count $preview_retry_windows) -eq 0; and test (count $notes_retry_windows) -eq 0
            break
        end

        ws_move_windows_to_space $target_space $finder_retry_windows $preview_retry_windows $notes_retry_windows

        set -l reconcile_phase final_review_reconcile
        if test "$attempt" -gt 1
            set reconcile_phase final_review_reconcile_$attempt
        end

        set windows_json_final (ws_query_windows $_flag_label $reconcile_phase); or return 1
    end

    if test -z "$preview_fallback_window"
        set -l preview_target_windows (echo $windows_json_final | workspace_app_key_windows --app-key preview --space $target_space --movable --nonempty-title)
        or return 1

        set -l preview_lingering_info (echo $windows_json_final | ws_jq -r --argjson apps "$preview_apps_json" --argjson s $target_space '
            first(
                .[]
                | select(.app as $app | $apps | index($app))
                | select(.space!=$s)
                | select(.["is-minimized"]==false)
                | select(.["can-move"]==true)
                | [.id, .space, .display]
                | @tsv
            ) // empty
        ')
        if test $status -ne 0
            return 1
        end

        if test -z "$preview_lingering_info" -a (count $preview_target_windows) -eq 0
            set preview_lingering_info (echo $windows_json_final | ws_jq -r --argjson apps "$preview_apps_json" --argjson s $target_space '
                first(
                    .[]
                    | select(.app as $app | $apps | index($app))
                    | select(.space!=$s)
                    | select(.["is-minimized"]==false)
                    | [.id, .space, .display]
                    | @tsv
                ) // empty
            ')
            if test $status -ne 0
                return 1
            end
        end

        if test -n "$preview_lingering_info"
            set -l preview_lingering_parts (string split \t -- "$preview_lingering_info")
            set preview_fallback_window $preview_lingering_parts[1]
            set preview_fallback_space $preview_lingering_parts[2]
            set preview_fallback_display $preview_lingering_parts[3]

            if test -z "$preview_fallback_window" -o -z "$preview_fallback_space" -o -z "$preview_fallback_display"
                echo "[WARN] $_flag_label found Preview outside the review target, but its fallback space metadata was incomplete" >&2
                return 1
            end

            set target_space (workspace_focus_space_fallback \
                --label $_flag_label \
                --space $preview_fallback_space \
                --source-display $preview_fallback_display \
                --target-display $target_display \
                --layout float \
                --phase preview-move-fallback \
                $cleanup_specs)
            or return 1

            set preview_fallback_space $target_space
            set preview_fallback_display $target_display

            workspace_evict_non_owned_windows_from_space \
                --caller $_flag_label \
                --space $target_space \
                --target-display $target_display \
                --allowed-app-regex "$review_app_regex"
            or return 1

            set windows_json_final (ws_query_windows $_flag_label preview_move_fallback_before_move)
            or return 1

            set finder_windows (echo $windows_json_final | workspace_app_key_windows --app-key finder --movable)
            or return 1
            set preview_movable_windows (echo $windows_json_final | workspace_app_key_windows --app-key preview --movable)
            or return 1
            set chatgpt_movable_windows (echo $windows_json_final | workspace_app_key_windows --app-key chatgpt --movable)
            or return 1

            for preview_window in $preview_movable_windows
                rm -f "$bad_window_dir/$preview_window" 2>/dev/null
            end

            set -l fallback_windows_to_move $finder_windows $preview_movable_windows $chatgpt_movable_windows
            if test "$notes_space_fallback_used" -ne 1
                set -l notes_move_windows (echo $windows_json_final | workspace_app_key_windows --app-key notes --movable)
                or return 1
                set -a fallback_windows_to_move $notes_move_windows
            end

            ws_move_windows_to_space $target_space $fallback_windows_to_move
            set windows_json_final (ws_query_windows $_flag_label preview_move_fallback); or return 1
        end
    end

    set finder_windows (echo $windows_json_final | workspace_app_key_windows --app-key finder --space $target_space --movable)
    or return 1
    set preview_movable_windows (echo $windows_json_final | workspace_app_key_windows --app-key preview --space $target_space --movable)
    or return 1
    set preview $preview_movable_windows[1]
    for preview_window in $preview_movable_windows
        rm -f "$bad_window_dir/$preview_window" 2>/dev/null
    end
    if test -z "$preview" -a -n "$preview_fallback_window"
        set preview $preview_fallback_window
    end

    set -l chatgpt_target_windows (echo $windows_json_final | workspace_app_key_windows --app-key chatgpt --space $target_space --movable)
    or return 1
    set -l chatgpt $chatgpt_target_windows[1]
    if test -z "$chatgpt" -a -n "$chatgpt_initial_info"
        set chatgpt (workspace_capture_app_window --app "$chatgpt_app" --caller $_flag_label --space $target_space)
        if test $status -eq 1
            return 1
        end
    end

    set -l notes_target_windows
    if test "$notes_space_fallback_used" -eq 1
        set notes_target_windows (echo $windows_json_final | ws_jq -r --argjson apps "$notes_apps_json" --argjson s $target_space '
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.space==$s)
            | select(.["is-minimized"]==false)
            | .id
        ')
        if test (count $notes_target_windows) -eq 0 -a -n "$notes_fallback_window"
            set notes_target_windows $notes_fallback_window
        end
    else
        set notes_target_windows (echo $windows_json_final | workspace_app_key_windows --app-key notes --space $target_space --movable)
        or return 1
    end

    if test -n "$_flag_finder_grid"
        for finder in $finder_windows
            ws_window $finder --grid $_flag_finder_grid
        end
    end

    if test -n "$preview" -a -n "$_flag_preview_grid"
        if test -n "$preview_fallback_window"
            ws_focus_space $target_space
            workspace_apply_app_key_grid_bounds \
                --app-key preview \
                --display $target_display \
                --grid $_flag_preview_grid \
                --caller $_flag_label \
                --all-windows

            if test "$preview_fallback_display" = "$target_display" -a "$preview_fallback_space" != "$target_space"
                set -l displays_json (ws_query_displays $_flag_label preview-bounce)
                if test $status -eq 0 -a -n "$displays_json"
                    set -l bounce_display (echo $displays_json | ws_jq -r --argjson target "$target_display" '
                        first(.[] | select(.index!=$target) | .index) // empty
                    ')

                    if test -n "$bounce_display"
                        ws_focus_space $target_space
                        workspace_apply_app_key_grid_bounds \
                            --app-key preview \
                            --display $bounce_display \
                            --grid 1:1:0:0:1:1 \
                            --caller $_flag_label \
                            --all-windows

                        ws_focus_space $target_space
                        workspace_apply_app_key_grid_bounds \
                            --app-key preview \
                            --display $target_display \
                            --grid $_flag_preview_grid \
                            --caller $_flag_label \
                            --all-windows
                    else
                        echo "[WARN] $_flag_label could not find an alternate display to space-bounce Preview" >&2
                    end
                end
            end
        else
            for preview_window in $preview_movable_windows
                ws_window $preview_window --grid $_flag_preview_grid
            end
        end
    end

    if test -n "$chatgpt" -a -n "$_flag_chatgpt_grid"
        ws_window $chatgpt --grid $_flag_chatgpt_grid
    end

    if test (count $notes_target_windows) -gt 0 -a -n "$_flag_notes_grid"
        if test "$notes_space_fallback_used" -eq 1
            workspace_apply_app_key_grid_bounds \
                --app-key notes \
                --display $target_display \
                --grid $_flag_notes_grid \
                --caller $_flag_label \
                --all-windows
        else
            for notes_window in $notes_target_windows
                ws_window $notes_window --grid $_flag_notes_grid
            end
        end
    end

    ws_focus_space $target_space

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    cleanup_unlabeled_empty_spaces $target_space
end

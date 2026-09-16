function __office_chatgpt_grid --description "Return the ChatGPT grid for an office workspace"
    set -l mode $argv[1]
    set -l primary_count $argv[2]

    switch "$mode"
        case wide
            echo 1:3:0:0:1:1
        case tall
            if test "$primary_count" -le 1
                echo 2:1:0:0:1:1
            else
                echo 2:2:0:0:1:1
            end
    end
end

function __office_primary_grid --description "Return a document window grid for an office workspace"
    set -l mode $argv[1]
    set -l index $argv[2]
    set -l primary_count $argv[3]
    set -l has_chatgpt $argv[4]

    if test "$has_chatgpt" -eq 1
        switch "$mode"
            case wide
                if test "$primary_count" -le 1
                    echo 1:3:1:0:2:1
                else if test "$primary_count" -eq 2
                    switch "$index"
                        case 1
                            echo 1:3:1:0:1:1
                        case 2
                            echo 1:3:2:0:1:1
                    end
                else
                    switch "$index"
                        case 1
                            echo 1:3:1:0:1:1
                        case 2
                            echo 2:3:2:0:1:1
                        case 3
                            echo 2:3:2:1:1:1
                    end
                end
            case tall
                if test "$primary_count" -le 1
                    echo 2:1:0:1:1:1
                else if test "$primary_count" -eq 2
                    switch "$index"
                        case 1
                            echo 2:2:1:0:1:1
                        case 2
                            echo 2:1:0:1:1:1
                    end
                else
                    switch "$index"
                        case 1
                            echo 2:2:1:0:1:1
                        case 2
                            echo 2:2:0:1:1:1
                        case 3
                            echo 2:2:1:1:1:1
                    end
                end
        end
    else
        switch "$mode"
            case wide
                if test "$primary_count" -le 1
                    echo 1:1:0:0:1:1
                else if test "$primary_count" -eq 2
                    switch "$index"
                        case 1
                            echo 1:2:0:0:1:1
                        case 2
                            echo 1:2:1:0:1:1
                    end
                else
                    switch "$index"
                        case 1
                            echo 1:3:0:0:1:1
                        case 2
                            echo 1:3:1:0:1:1
                        case 3
                            echo 1:3:2:0:1:1
                    end
                end
            case tall
                if test "$primary_count" -le 1
                    echo 1:1:0:0:1:1
                else if test "$primary_count" -eq 2
                    switch "$index"
                        case 1
                            echo 2:1:0:0:1:1
                        case 2
                            echo 2:1:0:1:1:1
                    end
                else
                    switch "$index"
                        case 1
                            echo 2:2:0:0:1:1
                        case 2
                            echo 2:2:1:0:1:1
                        case 3
                            echo 2:2:0:1:1:1
                        case 4
                            echo 2:2:1:1:1:1
                    end
                end
        end
    end
end

function office_apply_document_space --description "Apply an Office workspace for ChatGPT and document windows"
    argparse \
        'label=' \
        'display=' \
        'primary-app-key=' \
        'mode=' \
        dry-run \
        -- $argv
    or return 1

    if not set -q _flag_label; or not set -q _flag_display; or not set -q _flag_primary_app_key; or not set -q _flag_mode
        echo "usage: office_apply_document_space --label <label> --display <wide|tall> --primary-app-key <word|powerpoint> --mode <wide|tall> [--dry-run] [cleanup-spec ...]" >&2
        return 2
    end

    set -l cleanup_specs $argv
    set -l primary_app (workspace_app_name $_flag_primary_app_key)
    or return 1
    set -l chatgpt_app (workspace_app_name chatgpt)
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=office_apply_document_space\n"
        printf "label=%s\n" "$_flag_label"
        printf "display=%s\n" "$_flag_display"
        printf "mode=%s\n" "$_flag_mode"
        printf "apps=%s,%s\n" "$chatgpt_app" "$primary_app"
        printf "primary_app=%s\n" "$primary_app"
        printf "helper_app=%s\n" "$chatgpt_app"
        printf "cleanup=%s\n" "$cleanup_specs"
        return 0
    end

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    set -l windows_json (ws_query_windows $_flag_label initial)
    or return 1

    set -l primary_windows (echo $windows_json | workspace_app_key_windows --app-key $_flag_primary_app_key --movable)
    or return 1

    if test (count $primary_windows) -eq 0
        destroy_empty_labeled_space $_flag_label
        return 0
    end

    set -l target_display (workspace_resolve_display_role $_flag_display)
    or return $status

    set -l allowed_app_regex (workspace_app_regex $_flag_primary_app_key chatgpt)
    or return 1

    set -l target_space (find_or_create_labeled_space $_flag_label $target_display)
    if test -z "$target_space"
        return 1
    end

    set target_space (workspace_retarget_contaminated_space \
        $_flag_label \
        $_flag_label \
        $target_space \
        $target_display \
        "$allowed_app_regex")
    or return 1

    workspace_focus_labeled_space $_flag_label $target_space $target_display float
    or return 1

    ws_move_windows_to_space $target_space $primary_windows

    set -l chatgpt (workspace_capture_app_window --app-key chatgpt --caller $_flag_label --space $target_space)
    set -l chatgpt_status $status
    if test "$chatgpt_status" -eq 1
        return 1
    end

    set -l has_chatgpt 0
    if test -n "$chatgpt"
        set has_chatgpt 1
        set -l chatgpt_grid (__office_chatgpt_grid $_flag_mode (count $primary_windows))
        if test -n "$chatgpt_grid"
            ws_window $chatgpt --grid $chatgpt_grid
        end
    end

    for index in (seq 1 (count $primary_windows))
        set -l primary_grid (__office_primary_grid $_flag_mode $index (count $primary_windows) $has_chatgpt)
        if test -n "$primary_grid"
            ws_window $primary_windows[$index] --grid $primary_grid
        end
    end

    ws_focus_space $target_space

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    cleanup_unlabeled_empty_spaces $target_space
end

function __office_writing_wide_body --description "Collect Word and ChatGPT onto the wide office writing workspace and apply the standard writing layout"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured office_writing_wide $argv
        return $status
    end
    office_apply_document_space \
        --label office_writing_wide \
        --display wide \
        --mode wide \
        --primary-app-key word \
        office:tall $argv
end

function __office_slides_wide_body --description "Collect PowerPoint and ChatGPT onto the wide office slides workspace and apply the standard slides layout"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured office_slides_wide $argv
        return $status
    end
    office_apply_document_space \
        --label office_slides_wide \
        --display wide \
        --mode wide \
        --primary-app-key powerpoint \
        office:tall $argv
end

function __office_wide_body --description "Arrange all office wide workspaces and clean opposite-mode spaces"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured_mode office_wide $argv
        return $status
    end
    workspace_run_mode_steps office:tall -- office_writing_wide office_slides_wide $argv
end

function __office_writing_tall_body --description "Collect Word and ChatGPT onto the tall office writing workspace and apply the standard writing layout"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured office_writing_tall $argv
        return $status
    end
    office_apply_document_space \
        --label office_writing_tall \
        --display tall \
        --mode tall \
        --primary-app-key word \
        office:wide $argv
end

function __office_slides_tall_body --description "Collect PowerPoint and ChatGPT onto the tall office slides workspace and apply the standard slides layout"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured office_slides_tall $argv
        return $status
    end
    office_apply_document_space \
        --label office_slides_tall \
        --display tall \
        --mode tall \
        --primary-app-key powerpoint \
        office:wide $argv
end

function __office_tall_body --description "Arrange all office tall workspaces and clean opposite-mode spaces"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured_mode office_tall $argv
        return $status
    end
    workspace_run_mode_steps office:wide -- office_writing_tall office_slides_tall $argv
end

function office_writing_wide --description "Collect Word and ChatGPT onto the wide office writing workspace and apply the standard writing layout"
    workspace_run_finalized_entry --mode wide --command __office_writing_wide_body -- $argv
end

function office_slides_wide --description "Collect PowerPoint and ChatGPT onto the wide office slides workspace and apply the standard slides layout"
    workspace_run_finalized_entry --mode wide --command __office_slides_wide_body -- $argv
end

function office_wide --description "Arrange all office wide workspaces and clean opposite-mode spaces"
    workspace_run_finalized_entry --mode wide --command __office_wide_body -- $argv
end

function office_writing_tall --description "Collect Word and ChatGPT onto the tall office writing workspace and apply the standard writing layout"
    workspace_run_finalized_entry --mode tall --command __office_writing_tall_body -- $argv
end

function office_slides_tall --description "Collect PowerPoint and ChatGPT onto the tall office slides workspace and apply the standard slides layout"
    workspace_run_finalized_entry --mode tall --command __office_slides_tall_body -- $argv
end

function office_tall --description "Arrange all office tall workspaces and clean opposite-mode spaces"
    workspace_run_finalized_entry --mode tall --command __office_tall_body -- $argv
end

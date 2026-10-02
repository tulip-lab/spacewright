function __workspace_config_plan_grid --description "Return the grid for one configured window role"
    set -l plan $argv[1]
    set -l role $argv[2]
    printf "%s\n" "$plan" | jq -r --arg role "$role" 'first(.layout[] | select(.role == $role) | .grid) // empty'
end

function __workspace_config_plan_app_key --description "Return the app key for one configured window role"
    set -l plan $argv[1]
    set -l role $argv[2]
    printf "%s\n" "$plan" | jq -r --arg role "$role" 'first(.windows[] | select(.role == $role) | .app_key) // empty'
end

function __workspace_config_cleanup_specs --description "Return family:mode cleanup specs from a configured plan"
    set -l plan $argv[1]
    printf "%s\n" "$plan" | jq -r '.cleanup as $cleanup | if $cleanup then $cleanup.opposite_modes[] | $cleanup.family + ":" + . else empty end'
end

function __workspace_config_select_window --description "Select one configured window from a shared snapshot"
    set -l windows_json $argv[1]
    set -l plan $argv[2]
    set -l index $argv[3]
    set -e argv[1..3]
    set -l used_json '[]'
    if test (count $argv) -gt 0
        set used_json (printf '%s\n' $argv | jq -R 'tonumber' | jq -s .)
    end
    set -l app_names (printf "%s\n" "$plan" | jq -c --argjson i $index '.windows[$i].app_names')
    set -l selector (printf "%s\n" "$plan" | jq -c --argjson i $index '.windows[$i].selector // {}')
    printf "%s\n" "$windows_json" | jq -r \
        --argjson apps "$app_names" \
        --argjson selector "$selector" \
        --argjson used "$used_json" '
        first(
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.["is-minimized"] == false)
            | select(($selector.movable // false) == false or .["can-move"] == true)
            | select(($selector.visible // false) == false or .["is-visible"] == true)
            | select(($selector.non_empty_title // false) == false or ((.title // "") | length) > 0)
            | select(($selector.title_include // "") == "" or ((.title // "") | contains($selector.title_include)))
            | select(($selector.title_exclude // "") == "" or (((.title // "") | contains($selector.title_exclude)) | not))
            | select(($selector.role // "") == "" or ((.role // "") == $selector.role))
            | select(($selector.subrole // "") == "" or ((.subrole // "") == $selector.subrole))
            | select(.id as $id | ($used | index($id)) == null)
            | .id
        ) // empty'
end

function __workspace_run_configured_primary_helper --description "Run a configured required-primary and optional-helper workspace"
    set -l plan $argv[1]
    set -l dry_run $argv[2]
    set -l workspace_id (printf "%s\n" "$plan" | jq -r '.id')
    set -l primary_count (printf "%s\n" "$plan" | jq '[.windows[] | select(.role == "primary" and .required == true)] | length')
    set -l helper_count (printf "%s\n" "$plan" | jq '[.windows[] | select(.role == "helper" and .required == false)] | length')
    if test "$primary_count" -ne 1; or test "$helper_count" -gt 1
        echo "[WARN] $workspace_id primary_helper requires one required primary and at most one optional helper" >&2
        return 1
    end

    set -l primary_app_key (__workspace_config_plan_app_key "$plan" primary)
    set -l helper_app_key (__workspace_config_plan_app_key "$plan" helper)
    set -l primary_grid (__workspace_config_plan_grid "$plan" primary)
    set -l helper_grid (__workspace_config_plan_grid "$plan" helper)
    set -l primary_alone_grid (printf "%s\n" "$plan" | jq -r 'first(.primary_alone_layout[]? | select(.role == "primary") | .grid) // empty')
    if test -z "$primary_grid"
        echo "[WARN] $workspace_id primary_helper requires a primary grid action" >&2
        return 1
    end

    set -l apply_args \
        --label (printf "%s\n" "$plan" | jq -r '.label') \
        --caller "$workspace_id" \
        --display (printf "%s\n" "$plan" | jq -r '.display_role') \
        --layout (printf "%s\n" "$plan" | jq -r '.space_layout') \
        --primary-app-key "$primary_app_key" \
        --primary-grid "$primary_grid"

    if test -n "$primary_alone_grid"
        set -a apply_args --primary-alone-grid "$primary_alone_grid"
    end
    if test -n "$helper_app_key"
        if test -z "$helper_grid"
            echo "[WARN] $workspace_id helper requires a helper grid action" >&2
            return 1
        end
        set -a apply_args --helper-app-key "$helper_app_key" --helper-grid "$helper_grid"
        if test (printf "%s\n" "$plan" | jq -r 'first(.windows[] | select(.role == "helper") | .selector.visible) // false') = true
            set -a apply_args --helper-visible
        end
    end
    if test (printf "%s\n" "$plan" | jq -r '.runner_options.primary_space_fallback // false') = true
        set -a apply_args --primary-space-fallback
    end
    set -a apply_args (__workspace_config_cleanup_specs "$plan")

    if test "$dry_run" = 1
        workspace_apply_primary_helper_space $apply_args --dry-run
        return $status
    end

    set -l required_window (workspace_find_app_key_window --app-key "$primary_app_key" --caller "$workspace_id-config-preflight")
    set -l preflight_status $status
    if test "$preflight_status" -ne 0; or test -z "$required_window"
        echo "[WARN] $workspace_id required app is unavailable; no workspace changes were made" >&2
        return 1
    end
    workspace_apply_primary_helper_space $apply_args
end

function __workspace_run_configured_office_document --description "Run a configured Office multi-document workspace"
    set -l plan $argv[1]
    set -l dry_run $argv[2]
    set -l args \
        --label (printf "%s\n" "$plan" | jq -r '.label') \
        --display (printf "%s\n" "$plan" | jq -r '.display_role') \
        --mode (printf "%s\n" "$plan" | jq -r '.runner_options.mode') \
        --primary-app-key (__workspace_config_plan_app_key "$plan" primary)
    set -a args (__workspace_config_cleanup_specs "$plan")
    if test "$dry_run" = 1
        set -a args --dry-run
    end
    office_apply_document_space $args
end

function __workspace_run_configured_gtd_support --description "Run a configured GTD support workspace"
    set -l plan $argv[1]
    set -l dry_run $argv[2]
    set -l args \
        --label (printf "%s\n" "$plan" | jq -r '.label') \
        --display (printf "%s\n" "$plan" | jq -r '.display_role') \
        --dia-layout (printf "%s\n" "$plan" | jq -r '.runner_options.mode')
    set -a args (__workspace_config_cleanup_specs "$plan")
    if test "$dry_run" = 1
        set -a args --dry-run
    end
    gtd_apply_support_space $args
end

function __workspace_run_configured_gtd_review --description "Run a configured GTD review workspace"
    set -l plan $argv[1]
    set -l dry_run $argv[2]
    set -l args --label (printf "%s\n" "$plan" | jq -r '.label') --display (printf "%s\n" "$plan" | jq -r '.display_role')
    for role in finder preview chatgpt notes obsidian
        set -l grid (__workspace_config_plan_grid "$plan" $role)
        if test -n "$grid"
            set -a args --$role-grid "$grid"
        end
    end
    set -a args (__workspace_config_cleanup_specs "$plan")
    if test "$dry_run" = 1
        set -a args --dry-run
    end
    gtd_apply_review_space $args
end

function __workspace_run_configured_gtd_meeting --description "Run a configured GTD meeting workspace"
    set -l plan $argv[1]
    set -l dry_run $argv[2]
    set -l args \
        --label (printf "%s\n" "$plan" | jq -r '.label') \
        --display (printf "%s\n" "$plan" | jq -r '.display_role') \
        --zoom-grid (__workspace_config_plan_grid "$plan" zoom) \
        --teams-grid (__workspace_config_plan_grid "$plan" teams)
    set -a args (__workspace_config_cleanup_specs "$plan")
    if test "$dry_run" = 1
        set -a args --dry-run
    end
    gtd_apply_meeting_space $args
end

function __workspace_run_configured_gtd_ai --description "Run a configured GTD AI workspace"
    set -l plan $argv[1]
    set -l dry_run $argv[2]
    set -l args --label (printf "%s\n" "$plan" | jq -r '.label') --display (printf "%s\n" "$plan" | jq -r '.display_role')
    for role in hermes chatgpt obsidian notes
        set -l grid (__workspace_config_plan_grid "$plan" $role)
        if test -n "$grid"
            set -a args --$role-grid "$grid"
        end
    end
    set -a args (__workspace_config_cleanup_specs "$plan")
    if test "$dry_run" = 1
        set -a args --dry-run
    end
    gtd_apply_ai_space $args
end

function __workspace_run_configured_fixed_adapter --description "Run one closed, recovery-heavy configured adapter"
    set -l plan $argv[1]
    set -l dry_run $argv[2]
    set -l adapter (printf "%s\n" "$plan" | jq -r '.runner_options.adapter')
    set -l args
    if test "$dry_run" = 1
        set args --dry-run
    end
    switch "$adapter"
        case coding_control
            __coding_control_body $args
        case gtd_chat
            __gtd_chat_body $args
        case gtd_calendar
            __gtd_calendar_body $args
        case '*'
            echo "[WARN] unsupported fixed configured adapter: $adapter" >&2
            return 1
    end
end

function __workspace_run_configured_generic_layout --description "Run a declarative multi-window workspace"
    set -l plan $argv[1]
    set -l dry_run $argv[2]
    set -l workspace_id (printf "%s\n" "$plan" | jq -r '.id')
    if test "$dry_run" = 1
        printf "dry_run=workspace_apply_generic_layout\n"
        printf "workspace=%s\n" "$workspace_id"
        printf "label=%s\n" (printf "%s\n" "$plan" | jq -r '.label')
        printf "display=%s\n" (printf "%s\n" "$plan" | jq -r '.display_role')
        printf "%s\n" "$plan" | jq -r '.windows[] | "window=" + .role + ":" + .app_key + ":required=" + (.required|tostring)'
        printf "%s\n" "$plan" | jq -r '.layout[] | "grid=" + .role + ":" + .grid'
        return 0
    end

    set -l roles
    set -l window_ids
    set -l selected_ids
    set -l windows_json (ws_query_windows "$workspace_id-config-preflight" all)
    or begin
        echo "[WARN] $workspace_id could not query windows; no workspace changes were made" >&2
        return 1
    end
    set -l window_count (printf "%s\n" "$plan" | jq '.windows | length')
    for index in (seq 0 (math $window_count - 1))
        set -l role (printf "%s\n" "$plan" | jq -r --argjson i $index '.windows[$i].role')
        set -l app_key (printf "%s\n" "$plan" | jq -r --argjson i $index '.windows[$i].app_key')
        set -l required (printf "%s\n" "$plan" | jq -r --argjson i $index '.windows[$i].required')
        set -l window_id (__workspace_config_select_window "$windows_json" "$plan" $index $selected_ids)
        set -l find_status $status
        for retry in (seq 1 3)
            test -n "$window_id"; and break
            sleep 0.25
            set windows_json (ws_query_windows "$workspace_id-config-preflight" retry_$retry)
            or break
            set window_id (__workspace_config_select_window "$windows_json" "$plan" $index $selected_ids)
            set find_status $status
        end
        if test "$find_status" -eq 1; or test "$required" = true -a -z "$window_id"
            echo "[WARN] $workspace_id required role is unavailable: $role" >&2
            return 1
        end
        set -a roles "$role"
        if test -n "$window_id"
            set -a window_ids "$window_id"
            set -a selected_ids "$window_id"
        else
            set -a window_ids __missing__
        end
    end

    set -l target_display (workspace_resolve_display_role (printf "%s\n" "$plan" | jq -r '.display_role'))
    or return 1
    set -l target_space (workspace_prepare_labeled_space \
        (printf "%s\n" "$plan" | jq -r '.label') \
        "$target_display" \
        (printf "%s\n" "$plan" | jq -r '.space_layout'))
    or return 1

    if test (count $selected_ids) -gt 0
        ws_move_windows_to_space "$target_space" $selected_ids
        or return 1
    end
    for index in (seq 1 (count $roles))
        set -l window_id $window_ids[$index]
        test "$window_id" != __missing__; or continue
        set -l grid (__workspace_config_plan_grid "$plan" $roles[$index])
        test -n "$grid"; and ws_window "$window_id" --grid "$grid"
    end

    set -l selected_json '[]'
    if test (count $selected_ids) -gt 0
        set selected_json (printf '%s\n' $selected_ids | jq -R 'tonumber' | jq -s .)
    end
    set -l settled 0
    for attempt in (seq 1 4)
        set -l final_windows (ws_query_windows "$workspace_id-config-verify" final_$attempt)
        if test $status -eq 0
            jq -n -e --argjson ids "$selected_json" --argjson space "$target_space" --argjson windows "$final_windows" '
                all($ids[]; . as $id | any($windows[]; .id == $id and .space == $space))
            ' >/dev/null 2>&1
            and begin
                set settled 1
                break
            end
        end
        sleep 0.2
    end
    if test "$settled" -ne 1
        echo "[WARN] $workspace_id did not settle every selected window on Space $target_space" >&2
        echo "[INFO] Run 'spacewright config-plan $workspace_id' and 'workspace_verify --json $workspace_id'" >&2
        return 1
    end
end

function workspace_run_configured --description "Run one validated configured workspace through a closed runner adapter"
    argparse dry-run -- $argv
    or return 1
    set -l workspace_id $argv[1]
    if test -z "$workspace_id"
        echo "usage: workspace_run_configured <workspace> [--dry-run]" >&2
        return 2
    end
    set -l plan (workspace_config_plan "$workspace_id" | string collect)
    or return 1
    set -l dry_run 0
    if set -q _flag_dry_run
        set dry_run 1
    end
    switch (printf "%s\n" "$plan" | jq -r '.runner')
        case primary_helper
            __workspace_run_configured_primary_helper "$plan" $dry_run
        case office_document
            __workspace_run_configured_office_document "$plan" $dry_run
        case gtd_support
            __workspace_run_configured_gtd_support "$plan" $dry_run
        case gtd_review
            __workspace_run_configured_gtd_review "$plan" $dry_run
        case gtd_meeting
            __workspace_run_configured_gtd_meeting "$plan" $dry_run
        case gtd_ai
            __workspace_run_configured_gtd_ai "$plan" $dry_run
        case fixed_adapter
            __workspace_run_configured_fixed_adapter "$plan" $dry_run
        case generic_layout
            __workspace_run_configured_generic_layout "$plan" $dry_run
        case '*'
            echo "[WARN] $workspace_id uses an unsupported configured runner" >&2
            return 1
    end
end

function workspace_run_configured_mode --description "Run one configured ordered aggregate mode"
    argparse dry-run -- $argv
    or return 1
    set -l mode_id $argv[1]
    if test -z "$mode_id"
        echo "usage: workspace_run_configured_mode <mode> [--dry-run]" >&2
        return 2
    end
    set -l plan (workspace_config_plan "$mode_id" | string collect)
    or return 1
    if test (printf "%s\n" "$plan" | jq -r '.kind') != mode
        echo "[WARN] $mode_id is not a configured mode" >&2
        return 1
    end
    if set -q _flag_dry_run
        set -l dry_run_commands (printf "%s\n" "$plan" | jq -r '.steps[] | .workspace // .mode // .postprocessor | select(. != "workspace_reconcile_primary_fixed_spaces")')
        if string match -q 'work_*' -- "$mode_id"
            printf "dry_run=%s\n" "$mode_id"
            printf "commands=%s\n" $dry_run_commands
        else
            printf "dry_run=workspace_run_mode_steps\n"
            printf "cleanup=%s\n" (string join ' ' -- (printf "%s\n" "$plan" | jq -r '.cleanup[]?'))
            printf "commands=%s\n" (string join ' ' -- $dry_run_commands)
        end
        return 0
    end

    set -l cleanup_specs (printf "%s\n" "$plan" | jq -r '.cleanup[]?')
    set -l failed 0
    for spec in $cleanup_specs
        workspace_run_step "cleanup $spec" workspace_run_cleanup_specs $spec
        or set failed 1
    end
    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1
    set -l step_count (printf "%s\n" "$plan" | jq '.steps | length')
    for index in (seq 0 (math $step_count - 1))
        set -l step_kind (printf "%s\n" "$plan" | jq -r --argjson i $index '.steps[$i] | if has("workspace") then "workspace" elif has("mode") then "mode" else "postprocessor" end')
        set -l step_name (printf "%s\n" "$plan" | jq -r --argjson i $index '.steps[$i].workspace // .steps[$i].mode // .steps[$i].postprocessor')
        switch "$step_kind"
            case workspace
                if functions -q $step_name
                    workspace_run_step "$step_name" $step_name
                else
                    workspace_run_step "$step_name" workspace_run_configured "$step_name"
                end
                or set failed 1
            case mode
                if functions -q $step_name
                    workspace_run_step "$step_name" $step_name
                else
                    workspace_run_step "$step_name" workspace_run_configured_mode "$step_name"
                end
                or set failed 1
            case postprocessor
                if not functions -q $step_name
                    echo "[WARN] configured postprocessor is unavailable: $step_name" >&2
                    set failed 1
                    continue
                end
                workspace_run_step "$step_name" $step_name
                or set failed 1
        end
    end
    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end
    for spec in $cleanup_specs
        workspace_run_step "final cleanup $spec" workspace_run_cleanup_specs $spec
        or set failed 1
    end
    return $failed
end

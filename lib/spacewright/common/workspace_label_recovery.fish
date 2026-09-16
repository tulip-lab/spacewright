function __workspace_label_recovery_plan_json --description "Build a label-only recovery plan from snapshot JSON on stdin"
    set -l workspace $argv[1]
    if test -z "$workspace"
        return 2
    end

    set -l snapshot_json
    read -lz snapshot_json
    if test -z "$snapshot_json"
        return 1
    end

    set -l spec_json (workspace_observation_spec $workspace | string collect)
    or return $status
    set -l plan_json (printf "%s\n" "$snapshot_json" | __workspace_observation_plan_json $workspace | string collect)
    or return $status

    ws_jq -n \
        --argjson snapshot "$snapshot_json" \
        --argjson spec "$spec_json" \
        --argjson plan "$plan_json" '
        ([$plan.roles[] | (.selected_windows + .fallback_candidate_windows)[]]) as $owned_windows
        | ([$owned_windows[].space | select(. != null and . > 0)] | unique) as $candidate_spaces
        | (if ($candidate_spaces | length) == 1 then $candidate_spaces[0] else null end) as $candidate_space
        | (first($snapshot.spaces[] | select(.index == $candidate_space)) // null) as $candidate_space_info
        | ([$spec.roles[].app_names[]] | unique) as $allowed_apps
        | ([
            $snapshot.windows[]
            | select($candidate_space != null and .space == $candidate_space)
            | select((.["is-minimized"] // false) == false)
            | select(.app as $app | ($allowed_apps | index($app)) == null)
            | {id, app}
        ]) as $foreign_windows
        | ($owned_windows | length) as $actionable_count
        | (
            if $plan.target_display == null then "blocked_target_display"
            elif $plan.label_count > 1 then "blocked_duplicate_label"
            elif $plan.label_count == 1 then
                if $actionable_count == 0
                        or ($plan.target_space == $candidate_space and $plan.target_space_display == $plan.target_display)
                then "already_labeled"
                else "blocked_existing_label"
                end
            elif $actionable_count == 0 then "not_applicable"
            elif ($candidate_spaces | length) != 1 then "blocked_ambiguous_space"
            elif $candidate_space_info == null then "blocked_candidate_space"
            elif $candidate_space_info.display != $plan.target_display then "blocked_wrong_display"
            elif (($candidate_space_info.label // "") != "") then "blocked_space_labeled"
            elif ($foreign_windows | length) > 0 then "blocked_foreign_windows"
            else "ready"
            end
        ) as $status
        | {
            version: 1,
            workspace: $plan.workspace,
            label: $plan.label,
            read_only: true,
            status: $status,
            target_display: $plan.target_display,
            existing_space: $plan.target_space,
            candidate_spaces: $candidate_spaces,
            candidate_space: $candidate_space,
            candidate_display: ($candidate_space_info.display // null),
            candidate_label: ($candidate_space_info.label // null),
            owned_window_ids: [$owned_windows[].id] | unique,
            foreign_windows: $foreign_windows,
            foreign_window_ids: [$foreign_windows[].id],
            action: (
                if $status == "ready" then {
                    action: "label_space",
                    space: $candidate_space,
                    label: $plan.label
                } else null end
            ),
            applied: false
        }'
end

function __workspace_label_recovery_aggregate_json --description "Aggregate label-only recovery results from stdin"
    set -l apply_requested $argv[1]

    ws_jq -s --argjson apply_requested "$apply_requested" '
        {
            version: 1,
            read_only: ($apply_requested | not),
            apply_requested: $apply_requested,
            status: (
                if any(.[]; .status == "apply_failed") then "apply_failed"
                elif any(.[]; .status | startswith("blocked_")) then "blocked"
                elif any(.[]; .status == "restored") then "restored"
                elif any(.[]; .status == "ready") then "ready"
                elif all(.[]; .status == "not_applicable") then "not_applicable"
                else "no_change"
                end
            ),
            ok: (
                if $apply_requested then
                    all(.[]; ((.status | startswith("blocked_")) | not) and .status != "apply_failed")
                else true
                end
            ),
            results: .
        }'
end

function __workspace_label_recovery_print --description "Print a compact label-only recovery report"
    ws_jq -r '
        "mode=\(if .apply_requested then "apply" else "dry-run" end)",
        "status=\(.status)",
        (
            .results[]
            | "workspace=\(.workspace) status=\(.status) candidate_space=\(.candidate_space // "none") label=\(.label) applied=\(.applied)"
        )
    '
end

function workspace_restore_labels --description "Plan or explicitly apply safe label-only workspace recovery"
    argparse apply dry-run json -- $argv
    or return 2

    if set -q _flag_apply; and set -q _flag_dry_run
        echo "workspace_restore_labels: --apply and --dry-run are mutually exclusive" >&2
        return 2
    end

    set -l workspaces $argv
    if test (count $workspaces) -eq 0
        set workspaces (workspace_observation_workspaces)
    end

    for workspace in $workspaces
        workspace_observation_spec $workspace >/dev/null
        or return $status
    end

    set -l snapshot_json (workspace_snapshot | string collect)
    or return 1
    set -l recovery_results
    set -l blocked 0

    for workspace in $workspaces
        set -l recovery_json (printf "%s\n" "$snapshot_json" | __workspace_label_recovery_plan_json $workspace | string collect)
        or return $status
        set -a recovery_results "$recovery_json"

        if printf "%s\n" "$recovery_json" | ws_jq -e '.status | startswith("blocked_")' >/dev/null 2>&1
            set blocked 1
        end
    end

    if set -q _flag_apply; and test "$blocked" -eq 0
        set -l applied_results
        for recovery_json in $recovery_results
            set -l recovery_status (printf "%s\n" "$recovery_json" | ws_jq -r '.status')
            if test "$recovery_status" = ready
                set -l candidate_space (printf "%s\n" "$recovery_json" | ws_jq -r '.candidate_space')
                set -l label (printf "%s\n" "$recovery_json" | ws_jq -r '.label')

                if ws_yabai -m space "$candidate_space" --label "$label"
                    set recovery_json (printf "%s\n" "$recovery_json" | ws_jq '.read_only = false | .status = "restored" | .applied = true' | string collect)
                else
                    set recovery_json (printf "%s\n" "$recovery_json" | ws_jq '.read_only = false | .status = "apply_failed" | .applied = false' | string collect)
                end
            else
                set recovery_json (printf "%s\n" "$recovery_json" | ws_jq '.read_only = false' | string collect)
            end
            set -a applied_results "$recovery_json"
        end
        set recovery_results $applied_results
    else if set -q _flag_apply
        set -l blocked_results
        for recovery_json in $recovery_results
            set recovery_json (printf "%s\n" "$recovery_json" | ws_jq '.read_only = false' | string collect)
            set -a blocked_results "$recovery_json"
        end
        set recovery_results $blocked_results
    end

    set -l apply_requested false
    if set -q _flag_apply
        set apply_requested true
    end

    set -l aggregate_json (printf "%s\n" $recovery_results | __workspace_label_recovery_aggregate_json $apply_requested | string collect)
    or return 1

    if set -q _flag_json
        printf "%s\n" "$aggregate_json"
    else
        printf "%s\n" "$aggregate_json" | __workspace_label_recovery_print
    end

    printf "%s\n" "$aggregate_json" | ws_jq -e '.ok == true' >/dev/null 2>&1
end

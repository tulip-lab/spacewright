function workspace_snapshot --description "Capture one read-only workspace display, Space, and window snapshot"
    if test (count $argv) -ne 0
        echo "usage: workspace_snapshot" >&2
        return 2
    end

    set -l caller workspace_snapshot

    set -l displays_json (ws_query_displays $caller observation-displays | string collect)
    or return 1
    set -l spaces_json (ws_query_spaces $caller observation-spaces | string collect)
    or return 1
    set -l windows_json (ws_query_windows $caller observation-windows | string collect)
    or return 1

    ws_jq -n \
        --argjson displays "$displays_json" \
        --argjson spaces "$spaces_json" \
        --argjson windows "$windows_json" \
        '{
            version: 1,
            displays: $displays,
            spaces: $spaces,
            windows: $windows
        }'
end

function workspace_observation_workspaces --description "Print workspaces with read-only observation contracts"
    set -l mode (workspace_detect_display_mode 2>/dev/null)
    if not contains -- $mode solo wide tall
        set mode wide
    end

    spacewright_config_effective | ws_jq -r --arg mode "$mode" '
        . as $root
        | def expand($id):
            $root.modes[$id].steps[]
            | if .workspace then .workspace
              elif .mode then expand(.mode)
              else empty
              end;
        (reduce expand("work_" + $mode) as $id ([]; if index($id) == null then . + [$id] else . end))[]
    '
end

function workspace_observation_spec --description "Print the read-only observation contract for a supported workspace"
    set -l workspace $argv[1]

    if test (count $argv) -ne 1
        echo "usage: workspace_observation_spec <workspace>" >&2
        return 2
    end

    switch "$workspace"
        case gtd_meeting_wide
            set -l zoom_apps (workspace_app_names_json zoom | string collect)
            or return 1
            set -l teams_apps (workspace_app_names_json teams | string collect)
            or return 1

            ws_jq -n \
                --argjson zoom_apps "$zoom_apps" \
                --argjson teams_apps "$teams_apps" '
                {
                    version: 1,
                    workspace: "gtd_meeting_wide",
                    label: "gtd_meeting_wide",
                    display_role: "wide",
                    roles: [
                        {
                            role: "zoom",
                            app_names: $zoom_apps,
                            selection: "all",
                            exclude_mini_title: true,
                            fallback_space_owner: true,
                            layout: {
                                kind: "region",
                                region: "left",
                                grid: "1:2:0:0:1:1"
                            }
                        },
                        {
                            role: "teams",
                            app_names: $teams_apps,
                            selection: "all",
                            exclude_mini_title: true,
                            fallback_space_owner: true,
                            layout: {
                                kind: "region",
                                region: "right",
                                grid: "1:2:1:0:1:1"
                            }
                        }
                    ]
                }'
        case coding_control
            set -l warp_apps (workspace_app_names_json warp | string collect)
            or return 1
            set -l smartgit_apps (workspace_app_names_json smartgit | string collect)
            or return 1
            set -l keepassx_apps (workspace_app_names_json keepassx | string collect)
            or return 1
            set -l flclash_apps (workspace_app_names_json flclash thaw | string collect)
            or return 1
            set -l portfolio_performance_apps (workspace_app_names_json portfolio_performance | string collect)
            or return 1

            ws_jq -n \
                --argjson warp_apps "$warp_apps" \
                --argjson smartgit_apps "$smartgit_apps" \
                --argjson keepassx_apps "$keepassx_apps" \
                --argjson flclash_apps "$flclash_apps" \
                --argjson portfolio_performance_apps "$portfolio_performance_apps" '
                {
                    version: 1,
                    workspace: "coding_control",
                    label: "coding_control",
                    display_role: "primary",
                    roles: [
                        {
                            role: "warp",
                            app_names: $warp_apps,
                            selection: "first",
                            fallback_space_owner: false,
                            layout: {
                                kind: "region",
                                region: "top_two_thirds",
                                grid: "3:1:0:0:1:2"
                            }
                        },
                        {
                            role: "smartgit",
                            app_names: $smartgit_apps,
                            selection: "first",
                            fallback_space_owner: true,
                            layout: {
                                kind: "absolute",
                                x: 300,
                                y: 60,
                                width: 1200,
                                height: 1040,
                                tolerance: 8
                            }
                        },
                        {
                            role: "keepassx",
                            app_names: $keepassx_apps,
                            selection: "first",
                            fallback_space_owner: false,
                            layout: {kind: "none"}
                        },
                        {
                            role: "flclash",
                            app_names: $flclash_apps,
                            selection: "all",
                            fallback_space_owner: false,
                            layout: {
                                kind: "absolute",
                                x: 360,
                                y: 120,
                                width: 1200,
                                height: 1040,
                                tolerance: 8
                            }
                        },
                        {
                            role: "portfolio_performance",
                            app_names: $portfolio_performance_apps,
                            selection: "first",
                            fallback_space_owner: false,
                            layout: {
                                kind: "absolute",
                                x: 420,
                                y: 180,
                                width: 1220,
                                height: 852,
                                tolerance: 8
                            }
                        }
                    ]
                }'
        case '*'
            set -l plan_json (workspace_config_plan $workspace | string collect)
            if test $status -ne 0
                echo "[WARN] workspace observation is not configured for: $workspace" >&2
                return 2
            end

            printf "%s\n" "$plan_json" | ws_jq '
                def selection($runner; $role):
                    if $runner == "gtd_support" or $runner == "gtd_meeting" then "all"
                    elif $runner == "office_document" and $role == "primary" then "all"
                    elif $runner == "gtd_review" and ($role == "finder" or $role == "preview" or $role == "notes") then "all"
                    else "first"
                    end;
                def fallback_owner($runner; $role; $options):
                    ($runner == "primary_helper" and $role == "primary" and ($options.primary_space_fallback // false))
                    or ($runner == "gtd_review" and ($role == "preview" or $role == "notes"))
                    or ($runner == "gtd_meeting")
                    or ($runner == "fixed_adapter" and ($role == "smartgit" or $role == "dingtalk" or $role == "calendar"));
                def absolute_value($text; $index):
                    ($text // "") | split(":") | .[$index] | tonumber?;
                def action_layout($action):
                    if $action == null then {kind: "none"}
                    elif $action.grid != null then {kind: "grid", grid: $action.grid}
                    elif $action.move_abs != null and $action.resize_abs != null then {
                        kind: "absolute",
                        x: absolute_value($action.move_abs; 1),
                        y: absolute_value($action.move_abs; 2),
                        width: absolute_value($action.resize_abs; 1),
                        height: absolute_value($action.resize_abs; 2),
                        tolerance: 8
                    }
                    else {kind: "none"}
                    end;

                . as $plan
                | {
                    version: 1,
                    workspace: $plan.id,
                    label: $plan.label,
                    display_role: $plan.display_role,
                    roles: [
                        $plan.windows[] as $window
                        | (first($plan.layout[] | select(.role == $window.role)) // null) as $action
                        | {
                            role: $window.role,
                            app_names: $window.app_names,
                            selection: selection($plan.runner; $window.role),
                            exclude_mini_title: ($plan.runner == "gtd_meeting"),
                            fallback_space_owner: fallback_owner($plan.runner; $window.role; $plan.runner_options),
                            layout: action_layout($action)
                        }
                    ]
                }
            '
    end
end

function __workspace_observation_plan_json --description "Build a read-only workspace plan from snapshot JSON on stdin"
    set -l workspace $argv[1]
    if test -z "$workspace"
        return 2
    end

    set -l snapshot_json
    read -lz snapshot_json
    if test -z "$snapshot_json"
        echo "[WARN] workspace_plan received an empty snapshot" >&2
        return 1
    end

    set -l spec_json (workspace_observation_spec $workspace | string collect)
    or return $status
    set -l primary_uuid (get_workspace_primary_display_uuid 2>/dev/null)

    ws_jq -n \
        --argjson snapshot "$snapshot_json" \
        --argjson spec "$spec_json" \
        --arg primary_uuid "$primary_uuid" '
        def window_summary:
            {
                id,
                app,
                space,
                display,
                can_move: (.["can-move"] // false),
                frame: (.frame // null)
            };

        def target_display($role):
            ($snapshot.displays // []) as $displays
            | if ($displays | length) == 0 then null
              elif ($displays | length) == 1 then $displays[0].index
              elif $primary_uuid == "" then null
              elif $role == "primary" then
                  first($displays[] | select(.uuid == $primary_uuid) | .index) // null
              elif $role == "wide" then
                  first(
                      $displays[]
                      | select(.uuid != $primary_uuid)
                      | select(.frame.w > .frame.h)
                      | .index
                  )
                  // first($displays[] | select(.uuid != $primary_uuid) | .index)
                  // null
              elif $role == "tall" then
                  first(
                      $displays[]
                      | select(.uuid != $primary_uuid)
                      | select(.frame.h > .frame.w)
                      | .index
                  )
                  // first($displays[] | select(.uuid != $primary_uuid) | .index)
                  // null
              else null
              end;

        (target_display($spec.display_role)) as $target_display
        | [
            $spec.roles[]
            | . as $role
            | [
                $snapshot.windows[]
                | select(.app as $app | $role.app_names | index($app))
                | select((.["is-minimized"] // false) == false)
                | select(
                    ($role.exclude_mini_title // false) == false
                    or (((.title // "") | ascii_downcase | contains("mini")) | not)
                )
            ] as $present
            | [$present[] | select(.["can-move"] == true)] as $movable
            | (if $role.selection == "first" then $movable[0:1] else $movable end) as $selected
            | (if $role.fallback_space_owner then
                   [$present[] | select(.["can-move"] != true)][0:1]
               else [] end) as $fallback
            | {
                role: $role.role,
                app_names: $role.app_names,
                selection: $role.selection,
                layout: $role.layout,
                present_windows: [$present[] | window_summary],
                selected_windows: [$selected[] | window_summary],
                fallback_candidate_windows: [$fallback[] | window_summary],
                present_ids: [$present[].id],
                selected_ids: [$selected[].id],
                fallback_candidate_ids: [$fallback[].id],
                current_spaces: [$present[].space] | unique
            }
        ] as $raw_roles
        | (
            if ($spec.workspace | startswith("gtd_support_")) then
                ($spec.workspace | split("_")[-1]) as $mode
                | [
                    $raw_roles[]
                    | if .role != "dia" then .
                      else . as $role
                      | ($role.selected_windows | length) as $count
                      | $role.selected_windows | to_entries[]
                      | .key as $index
                      | .value as $window
                      | (
                          if $mode == "wide" then
                              (($count + 1) / 2 | floor) as $left_count
                              | ($count - $left_count) as $right_count
                              | if $index < $left_count then "\($left_count):2:0:\($index):1:1"
                                else "\($right_count):2:1:\($index - $left_count):1:1"
                                end
                          elif $count == 1 and $mode == "solo" then "1:1:0:0:1:1"
                          elif $count == 1 then "2:1:0:1:1:1"
                          elif $count == 2 then "2:1:0:\($index):1:1"
                          elif $count == 3 and $index < 2 then "2:2:\($index):0:1:1"
                          elif $count == 3 then "2:1:0:1:1:1"
                          else (($count + 1) / 2 | floor) as $rows
                              | "\($rows):2:\($index % 2):\(($index / 2) | floor):1:1"
                          end
                        ) as $grid
                      | $role + {
                          selected_windows: [$window],
                          selected_ids: [$window.id],
                          fallback_candidate_windows: [],
                          fallback_candidate_ids: [],
                          layout: {kind: "grid", grid: $grid}
                        }
                      end
                ]
            else $raw_roles
            end
          ) as $roles
        | [$snapshot.spaces[] | select((.label // "") == $spec.label)] as $label_spaces
        | (if ($label_spaces | length) == 1 then $label_spaces[0] else null end) as $target_space_info
        | ($target_space_info.index // null) as $target_space
        | ([$spec.roles[].app_names[]] | unique) as $allowed_apps
        | [
            $snapshot.windows[]
            | select($target_space != null and .space == $target_space)
            | select((.["is-minimized"] // false) == false)
            | select(.app as $app | ($allowed_apps | index($app)) == null)
            | window_summary
        ] as $foreign_windows
        | ($roles | map((.selected_ids + .fallback_candidate_ids) | length) | add // 0) as $actionable_count
        | {
            version: 1,
            workspace: $spec.workspace,
            read_only: true,
            label: $spec.label,
            display_role: $spec.display_role,
            target_display: $target_display,
            target_display_frame: (
                first($snapshot.displays[] | select(.index == $target_display) | .frame) // null
            ),
            target_space: $target_space,
            target_space_display: ($target_space_info.display // null),
            label_count: ($label_spaces | length),
            status: (
                if $target_display == null then "blocked_target_display"
                elif ($label_spaces | length) > 1 then "blocked_duplicate_label"
                elif $actionable_count == 0 then "not_applicable"
                elif ($label_spaces | length) == 1 then "ready_existing"
                else "ready_create"
                end
            ),
            roles: $roles,
            foreign_windows: $foreign_windows,
            foreign_window_ids: [$foreign_windows[].id],
            warnings: [
                if $target_display == null then "target_display_unresolved" else empty end,
                if ($label_spaces | length) > 1 then "duplicate_workspace_label" else empty end,
                if ($foreign_windows | length) > 0 then "foreign_windows_on_target" else empty end,
                (
                    $roles[]
                    | select((.fallback_candidate_ids | length) > 0)
                    | "fallback_candidate:" + .role
                )
            ],
            actions: [
                if $actionable_count > 0 and $target_display != null then {
                    action: "prepare_space",
                    label: $spec.label,
                    target_display: $target_display,
                    existing_space: $target_space
                } else empty end,
                (
                    $roles[]
                    | select((.selected_ids | length) > 0)
                    | {
                        action: "move_and_layout",
                        role,
                        window_ids: .selected_ids,
                        layout
                    }
                ),
                (
                    $roles[]
                    | select((.fallback_candidate_ids | length) > 0)
                    | {
                        action: "fallback_space_candidate",
                        role,
                        window_ids: .fallback_candidate_ids,
                        layout
                    }
                )
            ]
        }'
end

function __workspace_observation_print_plan --description "Print a compact workspace plan"
    ws_jq -r '
        "workspace=\(.workspace)",
        "read_only=\(.read_only)",
        "status=\(.status)",
        "target_display=\(.target_display // "unresolved")",
        "target_space=\(.target_space // "none")",
        (
            .roles[]
            | "role=\(.role) present=\(.present_ids | join(",")) selected=\(.selected_ids | join(",")) fallback=\(.fallback_candidate_ids | join(",")) spaces=\(.current_spaces | join(","))"
        ),
        (.warnings[] | "warning=\(.)")
    '
end

function workspace_plan --description "Show a read-only live-state plan for a supported workspace"
    argparse json -- $argv
    or return 2

    if test (count $argv) -ne 1
        echo "usage: workspace_plan [--json] <workspace>" >&2
        return 2
    end

    set -l workspace $argv[1]
    workspace_observation_spec $workspace >/dev/null
    or return $status

    set -l snapshot_json (workspace_snapshot | string collect)
    or return 1
    set -l plan_json (printf "%s\n" "$snapshot_json" | __workspace_observation_plan_json $workspace | string collect)
    or return $status

    if set -q _flag_json
        printf "%s\n" "$plan_json"
    else
        printf "%s\n" "$plan_json" | __workspace_observation_print_plan
    end
end

function __workspace_observation_verify_json --description "Verify a workspace plan against its immutable snapshot"
    set -l plan_json
    read -lz plan_json
    if test -z "$plan_json"
        return 1
    end

    printf "%s\n" "$plan_json" | ws_jq '
        def absolute_value: if . < 0 then -. else . end;

        def layout_ok($layout; $display_frame):
            if $layout.kind == "none" then true
            elif .frame == null or $display_frame == null then false
            elif $layout.kind == "region" and $layout.region == "left" then
                (.frame.x + (.frame.w / 2)) <= ($display_frame.x + ($display_frame.w / 2))
            elif $layout.kind == "region" and $layout.region == "right" then
                (.frame.x + (.frame.w / 2)) >= ($display_frame.x + ($display_frame.w / 2))
            elif $layout.kind == "region" and $layout.region == "top_two_thirds" then
                .frame.y <= ($display_frame.y + ($display_frame.h * 0.15))
                and .frame.h >= ($display_frame.h * 0.55)
            elif $layout.kind == "absolute" then
                ((.frame.x - ($display_frame.x + $layout.x)) | absolute_value) <= ($layout.tolerance // 8)
                and ((.frame.y - ($display_frame.y + $layout.y)) | absolute_value) <= ($layout.tolerance // 8)
                and ((.frame.w - $layout.width) | absolute_value) <= ($layout.tolerance // 8)
                and ((.frame.h - $layout.height) | absolute_value) <= ($layout.tolerance // 8)
            elif $layout.kind == "grid" then
                ($layout.grid | split(":") | map(tonumber)) as $grid
                | ($grid[0]) as $rows
                | ($grid[1]) as $columns
                | ($grid[2]) as $column
                | ($grid[3]) as $row
                | ($grid[4]) as $column_span
                | ($grid[5]) as $row_span
                | (.frame.x + (.frame.w / 2)) as $center_x
                | (.frame.y + (.frame.h / 2)) as $center_y
                | ($display_frame.x + ($display_frame.w * $column / $columns)) as $min_x
                | ($display_frame.x + ($display_frame.w * ($column + $column_span) / $columns)) as $max_x
                | ($display_frame.y + ($display_frame.h * $row / $rows)) as $min_y
                | ($display_frame.y + ($display_frame.h * ($row + $row_span) / $rows)) as $max_y
                | $center_x >= $min_x and $center_x <= $max_x
                and $center_y >= $min_y and $center_y <= $max_y
            else false
            end;

        . as $plan
        | ([$plan.roles[] | (.selected_windows + .fallback_candidate_windows)[]]) as $expected_windows
        | ([$expected_windows[] | select(.space != $plan.target_space) | .id]) as $off_target_ids
        | ([
            $plan.roles[] as $role
            | ($role.selected_windows + $role.fallback_candidate_windows)[]
            | select((layout_ok($role.layout; $plan.target_display_frame)) | not)
            | .id
        ]) as $failed_layout_ids
        | ($expected_windows | length) as $actionable_count
        | [
            {
                name: "target_display_resolved",
                ok: ($plan.target_display != null),
                actual: $plan.target_display
            },
            {
                name: "label_unique",
                ok: (
                    if $actionable_count > 0 then $plan.label_count == 1
                    else $plan.label_count <= 1
                    end
                ),
                actual: $plan.label_count
            },
            {
                name: "label_on_target_display",
                ok: (
                    if $actionable_count == 0 and $plan.label_count == 0 then true
                    else $plan.target_space_display == $plan.target_display
                    end
                ),
                expected: $plan.target_display,
                actual: $plan.target_space_display
            },
            {
                name: "owned_windows_on_target",
                ok: (($off_target_ids | length) == 0),
                expected_space: $plan.target_space,
                off_target_ids: $off_target_ids
            },
            {
                name: "no_foreign_windows",
                ok: (($plan.foreign_window_ids | length) == 0),
                foreign_window_ids: $plan.foreign_window_ids
            },
            {
                name: "layout",
                ok: (($failed_layout_ids | length) == 0),
                failed_window_ids: $failed_layout_ids
            }
        ] as $checks
        | {
            version: 1,
            workspace: $plan.workspace,
            read_only: true,
            status: (
                if $plan.status == "not_applicable" and all($checks[]; .ok) then "not_applicable"
                elif all($checks[]; .ok) then "satisfied"
                else "drift"
                end
            ),
            ok: all($checks[]; .ok),
            target_display: $plan.target_display,
            target_space: $plan.target_space,
            checks: $checks,
            warnings: $plan.warnings
        }'
end

function __workspace_observation_verify_all_json --description "Verify every observed workspace against one snapshot"
    set -l snapshot_json
    read -lz snapshot_json
    if test -z "$snapshot_json"
        return 1
    end

    set -l plan_results
    for workspace in (workspace_observation_workspaces)
        set -l plan_json (printf "%s\n" "$snapshot_json" | __workspace_observation_plan_json $workspace | string collect)
        or return $status
        set -a plan_results "$plan_json"
    end

    set -l ordered_plans (printf "%s\n" $plan_results | ws_jq -s -c '
        . as $plans
        | to_entries[] as $entry
        | ([range($entry.key + 1; $plans | length) as $index
            | $plans[$index].roles[]
            | (.selected_ids + .fallback_candidate_ids)[]] | unique) as $later_owned
        | $entry.value
        | .roles |= map(
            .selected_windows |= map(select(.id as $id | ($later_owned | index($id)) == null))
            | .fallback_candidate_windows |= map(select(.id as $id | ($later_owned | index($id)) == null))
            | .selected_ids = [.selected_windows[].id]
            | .fallback_candidate_ids = [.fallback_candidate_windows[].id]
        )
    ')
    or return 1

    set -l verification_results
    for plan_json in $ordered_plans
        set -l verification_json (printf "%s\n" "$plan_json" | __workspace_observation_verify_json | string collect)
        or return 1
        set -a verification_results "$verification_json"
    end

    printf "%s\n" $verification_results | ws_jq -s '
        {
            version: 1,
            read_only: true,
            status: (
                if any(.[]; .ok == false) then "drift"
                elif all(.[]; .status == "not_applicable") then "not_applicable"
                else "satisfied"
                end
            ),
            ok: all(.[]; .ok == true),
            counts: {
                satisfied: ([.[] | select(.status == "satisfied")] | length),
                drift: ([.[] | select(.status == "drift")] | length),
                not_applicable: ([.[] | select(.status == "not_applicable")] | length)
            },
            results: .
        }'
end

function __workspace_observation_print_verification_summary --description "Print all observed workspace verification results"
    ws_jq -r '
        "read_only=\(.read_only)",
        (.results[] | "workspace=\(.workspace) status=\(.status) ok=\(.ok)"),
        "summary=\(.status) satisfied=\(.counts.satisfied) drift=\(.counts.drift) not_applicable=\(.counts.not_applicable)"
    '
end

function __workspace_observation_print_verification --description "Print a compact workspace verification report"
    ws_jq -r '
        "workspace=\(.workspace)",
        "read_only=\(.read_only)",
        "status=\(.status)",
        "ok=\(.ok)",
        (.checks[] | "check=\(.name) ok=\(.ok)")
    '
end

function workspace_verify --description "Verify a supported workspace against a read-only live-state snapshot"
    argparse json all -- $argv
    or return 2

    if set -q _flag_all
        if test (count $argv) -ne 0
            echo "usage: workspace_verify [--json] --all" >&2
            return 2
        end

        set -l snapshot_json (workspace_snapshot | string collect)
        or return 1
        set -l verification_json (printf "%s\n" "$snapshot_json" | __workspace_observation_verify_all_json | string collect)
        or return 1

        if set -q _flag_json
            printf "%s\n" "$verification_json"
        else
            printf "%s\n" "$verification_json" | __workspace_observation_print_verification_summary
        end

        printf "%s\n" "$verification_json" | ws_jq -e '.ok == true' >/dev/null 2>&1
        return $status
    end

    if test (count $argv) -ne 1
        echo "usage: workspace_verify [--json] <workspace> | workspace_verify [--json] --all" >&2
        return 2
    end

    set -l workspace $argv[1]
    workspace_observation_spec $workspace >/dev/null
    or return $status

    set -l snapshot_json (workspace_snapshot | string collect)
    or return 1
    set -l plan_json (printf "%s\n" "$snapshot_json" | __workspace_observation_plan_json $workspace | string collect)
    or return $status
    set -l verification_json (printf "%s\n" "$plan_json" | __workspace_observation_verify_json | string collect)
    or return 1

    if set -q _flag_json
        printf "%s\n" "$verification_json"
    else
        printf "%s\n" "$verification_json" | __workspace_observation_print_verification
    end

    printf "%s\n" "$verification_json" | ws_jq -e '.ok == true' >/dev/null 2>&1
end

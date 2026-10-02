function workspace_space_occupant_windows_json --description "Return non-sticky windows that make a Space nonempty"
    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        set windows_json '[]'
    end

    # These helpers are optional product integrations, not configuration
    # requirements.  A portable v2 configuration may omit any of them, so do
    # not route this lookup through the strict workspace_app_names helper.
    set -l nonoccupying_ghost_apps (spacewright_config_effective | ws_jq -c '
        [
            .apps.word.names[]?,
            .apps.powerpoint.names[]?,
            .apps.input_source_pro.names[]?
        ] | unique
    ')
    or return 1

    echo $windows_json | ws_jq -c --argjson ghost_apps "$nonoccupying_ghost_apps" '
        def nonoccupying_ghost:
            (.app as $app | $ghost_apps | index($app)) != null
            and ((.title // "") == "")
            and ((.role // "") == "")
            and ((.subrole // "") == "")
            and (.["can-move"] != true);

        [.[]
            | select(.["is-sticky"] != true)
            | select(nonoccupying_ghost | not)]
    '
end

function workspace_cleanup_empty_spaces --description "Destroy live-empty Spaces except Home and one survivor per display"
    argparse 'home-uuid=' 'focus-uuid=' -- $argv
    or return 1

    set -l home_uuid ""
    if set -q _flag_home_uuid
        set home_uuid $_flag_home_uuid
    end

    set -l focus_uuid ""
    if set -q _flag_focus_uuid
        set focus_uuid $_flag_focus_uuid
    end

    set -l spaces_json (ws_query_spaces workspace_cleanup_empty_spaces spaces)
    or return 1
    set -l windows_json (ws_query_windows workspace_cleanup_empty_spaces windows)
    or return 1
    set -l occupant_windows_json (echo $windows_json | workspace_space_occupant_windows_json)
    or return 1

    set -l candidates (echo $spaces_json | ws_jq -r \
        --arg home "$home_uuid" \
        --argjson windows "$occupant_windows_json" '
            def ordinary_count($space):
                [$windows[] | select(.space==$space.index)] | length;

            group_by(.display)
            | map(
                . as $group
                | (
                    ([$group[] | select(.uuid==$home)] | first)
                    // ([$group[] | select(ordinary_count(.)>0)] | sort_by(.index) | first)
                    // ($group | sort_by(.index) | first)
                  ) as $survivor
                | [$group[]
                    | select(.uuid != $survivor.uuid)
                    | select((.label // "") == "" or ((.label // "") | test("^sandbox_(solo|wide|tall)$")))
                    | select(.label != "coding_control")
                    | select(.label != "gtd_chat")
                    | select(.label != "gtd_calendar")
                    | select(ordinary_count(.)==0)]
              )
            | add // []
            | sort_by(.index) | reverse | .[]
            | [.uuid, (.index|tostring), (.display|tostring)] | @tsv
        ')
    or return 1

    for candidate in $candidates
        set -l parts (string split \t -- "$candidate")
        set -l uuid $parts[1]
        set -l live_spaces (ws_query_spaces workspace_cleanup_empty_spaces "before-destroy-$uuid")
        or return 1
        set -l live_windows (ws_query_windows workspace_cleanup_empty_spaces "before-destroy-$uuid")
        or return 1
        set -l live_occupant_windows (echo $live_windows | workspace_space_occupant_windows_json)
        or return 1

        set -l live_info (echo $live_spaces | ws_jq -r --arg uuid "$uuid" '
            first(.[] | select(.uuid==$uuid) | [.index, .display] | @tsv) // empty
        ')
        or return 1
        if test -z "$live_info"
            continue
        end

        set -l live_parts (string split \t -- "$live_info")
        set -l live_index $live_parts[1]
        set -l display $live_parts[2]
        echo $live_occupant_windows | ws_jq -e --argjson space $live_index \
            'any(.[]; .space==$space)' >/dev/null
        and continue

        if test -n "$focus_uuid" -a "$uuid" = "$focus_uuid"
            set -l safe_index (echo $live_spaces | ws_jq -r \
                --argjson display $display \
                --arg uuid "$uuid" \
                --arg home "$home_uuid" \
                --argjson windows "$live_occupant_windows" '
                    def ordinary_count($space):
                        [$windows[] | select(.space==$space.index)] | length;

                    first(.[]
                        | select(.display==$display and .uuid!=$uuid)
                        | select(.uuid==$home or ordinary_count(.)>0)
                        | .index)
                    // first(.[] | select(.display==$display and .uuid!=$uuid) | .index)
                    // empty
                ')
            if test -z "$safe_index"
                return 1
            end
            ws_focus_space $safe_index >/dev/null 2>&1
            or return 1
        end

        ws_yabai -m space $live_index --destroy >/dev/null 2>&1
        or return 1
    end
end

function workspace_finalize_mode --description "Collect Sandbox, clean, order, verify, and restore focus"
    set -l mode $argv[1]
    if test "$mode" = auto
        set mode (workspace_detect_display_mode)
        or return 1
    end
    if not contains -- $mode solo wide tall
        echo "usage: workspace_finalize_mode <solo|wide|tall|auto>" >&2
        return 2
    end

    set -l primary_display (resolve_workspace_primary_display)
    or return 1
    set -l target_display $primary_display
    if test "$mode" != solo
        set target_display (workspace_resolve_display_role $mode)
        or return 1
    end
    set -l spaces_json (ws_query_spaces workspace_finalize_mode initial_spaces)
    or return 1

    set -l home_info (echo $spaces_json | workspace_home_space_info --display $primary_display)
    or return 1
    set -l home_uuid ""
    set -l home_index 0
    if test -n "$home_info"
        set -l home_parts (string split \t -- "$home_info")
        set home_uuid $home_parts[1]
        set home_index $home_parts[2]
    end

    set -l current_json (ws_query_current_space workspace_finalize_mode focus)
    or return 1
    set -l focus_uuid (echo $current_json | ws_jq -r '.uuid // empty')
    or return 1

    set -l failed 0
    workspace_apply_sandbox --mode $mode --home-space $home_index --display $target_display
    or set failed 1

    set -l cleanup_args --focus-uuid $focus_uuid
    if test -n "$home_uuid"
        set -a cleanup_args --home-uuid $home_uuid
    end
    if test $failed -eq 0
        workspace_cleanup_empty_spaces $cleanup_args
        or set failed 1
    end
    if test $failed -eq 0
        workspace_order_and_verify_mode_spaces $mode
        or set failed 1
    end

    set spaces_json (ws_query_spaces workspace_finalize_mode final_spaces)
    or return 1
    set -l focus_index (echo $spaces_json | ws_jq -r \
        --arg focus "$focus_uuid" \
        --arg home "$home_uuid" '
            first(.[] | select(.uuid==$focus) | .index)
            // first(.[] | select($home!="" and .uuid==$home) | .index)
            // (sort_by(.index) | first | .index)
            // empty
        ')
    or return 1
    if test -n "$focus_index"
        ws_focus_space $focus_index >/dev/null 2>&1
        or return 1
    end

    return $failed
end

function workspace_run_finalized_entry --description "Run an entry and finalize only at the outermost scope"
    argparse 'mode=' 'command=' -- $argv
    or return 1

    if not set -q _flag_mode; or not contains -- $_flag_mode solo wide tall auto
        echo "usage: workspace_run_finalized_entry --mode <solo|wide|tall|auto> --command <function> -- [args...]" >&2
        return 2
    end
    if not set -q _flag_command; or not functions -q $_flag_command
        echo "usage: workspace_run_finalized_entry --mode <solo|wide|tall|auto> --command <function> -- [args...]" >&2
        return 2
    end

    set -l outermost 0
    set -l restart_generation_before 0
    if not set -q __WORKSPACE_FINALIZATION_DEPTH; or test "$__WORKSPACE_FINALIZATION_DEPTH" -eq 0
        set outermost 1
        set -g __WORKSPACE_FINALIZATION_MODE $_flag_mode
        set -g __WORKSPACE_FINALIZATION_DEPTH 0
        if set -q __WORKSPACE_YABAI_RESTART_GENERATION
            set restart_generation_before $__WORKSPACE_YABAI_RESTART_GENERATION
        end
    end
    set -g __WORKSPACE_FINALIZATION_DEPTH (math $__WORKSPACE_FINALIZATION_DEPTH + 1)

    $_flag_command $argv
    set -l body_status $status

    set -l restart_generation_after 0
    if set -q __WORKSPACE_YABAI_RESTART_GENERATION
        set restart_generation_after $__WORKSPACE_YABAI_RESTART_GENERATION
    end
    if test $outermost -eq 1
        and not contains -- --dry-run $argv
        and test "$restart_generation_after" -ne "$restart_generation_before"
        echo "[INFO] workspace yabai restarted during layout; replaying the complete workspace once" >&2
        set -lx WORKSPACE_DISABLE_YABAI_AUTO_RESTART 1
        $_flag_command $argv
        set body_status $status
    end

    set -g __WORKSPACE_FINALIZATION_DEPTH (math $__WORKSPACE_FINALIZATION_DEPTH - 1)

    set -l final_status 0
    if test $outermost -eq 1
        if contains -- --dry-run $argv
            printf "finalization_mode=%s\n" "$__WORKSPACE_FINALIZATION_MODE"
            if contains -- $__WORKSPACE_FINALIZATION_MODE solo wide tall auto
                printf "finalization_steps=sandbox cleanup order_verify restore_focus\n"
            else
                printf "finalization_steps=none\n"
            end
        else if contains -- $__WORKSPACE_FINALIZATION_MODE solo wide tall auto; and test "$WORKSPACE_SKIP_FINALIZATION" != 1
            workspace_finalize_mode $__WORKSPACE_FINALIZATION_MODE
            set final_status $status
        end

        set -e __WORKSPACE_FINALIZATION_MODE
        set -e __WORKSPACE_FINALIZATION_DEPTH
    end

    if test $body_status -ne 0
        return $body_status
    end
    return $final_status
end

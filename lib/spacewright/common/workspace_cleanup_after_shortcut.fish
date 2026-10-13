function workspace_cleanup_after_shortcut --description "Remove empty managed Spaces after a successful shortcut, including a layout no-op"
    argparse dry-run -- $argv
    or return 2
    if not set -q _flag_dry_run; and not workspace_execution_owned
        command node "$SPACEWRIGHT_PACKAGE_ROOT/configurator/execution-cli.mjs" exec fish --no-config -c 'source "$SPACEWRIGHT_PACKAGE_ROOT/conf.d/spacewright.fish"; or exit 1; source "$SPACEWRIGHT_ROOT/common/workspace_cleanup_after_shortcut.fish"; workspace_cleanup_after_shortcut'
        return $status
    end

    set -l config (spacewright_config_effective | string collect)
    or return 1
    set -l policy (printf '%s\n' "$config" | ws_jq -r '.settings.cleanupEmptySpaces // "managed"')
    or return 1
    test "$policy" != none; or return 0
    contains -- "$policy" managed all; or return 1
    set -l labels (printf '%s\n' "$config" | ws_jq -c '[.workspaces[]?.label] | unique')
    or return 1
    set -l spaces (ws_query_spaces workspace_cleanup_after_shortcut initial)
    or return 1
    set -l windows (ws_query_windows workspace_cleanup_after_shortcut initial)
    or return 1
    set -l initial_occupants (printf '%s\n' "$windows" | workspace_space_occupant_windows_json)
    or return 1
    set -l current (ws_query_current_space workspace_cleanup_after_shortcut focus)
    or return 1
    set -l focus_uuid (printf '%s\n' "$current" | ws_jq -r '.uuid')
    set -l primary (resolve_workspace_primary_display)
    or return 1
    # Home is only the leading unlabeled Space on the primary display. An
    # arbitrary later blank Space left by a window move is not Home.
    set -l home (printf '%s\n' "$spaces" | ws_jq -r --argjson display "$primary" '
        [.[] | select(.display == $display)] | sort_by(.index) | first
        | select(.label == "") | .uuid // empty
    ')
    or return 1
    set -l candidates (printf '%s\n' "$spaces" | ws_jq -r --argjson labels "$labels" --arg home "$home" --argjson windows "$initial_occupants" '
        group_by(.display) | map(
            sort_by(.index) | . as $lane
            | (first(.[] | select(.uuid == $home))
                // first(.[] | . as $space | select(any($windows[]; .space == $space.index)))
                // .[0]) as $survivor
            | [.[] | select(.uuid != $survivor.uuid)]
        ) | add // [] | sort_by(.index) | reverse | .[]
        | select(.label == "" or (.label | test("^sandbox_(solo|wide|tall)$")) or (.label as $label | $labels | index($label) != null))
        | [.uuid, .label, (.display | tostring)] | @tsv
    ')
    or return 1

    set -l removed 0
    for candidate in $candidates
        set -l fields (string split \t -- "$candidate")
        set -l uuid $fields[1]
        set -l live_spaces (ws_query_spaces workspace_cleanup_after_shortcut "before-$uuid")
        or return 1
        set -l live_windows (ws_query_windows workspace_cleanup_after_shortcut "before-$uuid")
        or return 1
        set -l occupants (printf '%s\n' "$live_windows" | workspace_space_occupant_windows_json)
        or return 1
        set -l index (printf '%s\n' "$live_spaces" | ws_jq -r \
            --arg uuid "$uuid" --arg label "$fields[2]" --argjson display "$fields[3]" --argjson windows "$occupants" '
            . as $spaces | first(.[] | select(.uuid == $uuid and .label == $label and .display == $display)
            | . as $space
            | select([$spaces[] | select(.display == $display)] | length > 1)
            | select(any($windows[]; .space == $space.index) | not) | .index) // empty
        ')
        or return 1
        test -n "$index"; or continue
        if set -q _flag_dry_run
            printf 'would_remove_empty_space=%s label=%s\n' "$uuid" "$fields[2]"
            continue
        end
        ws_yabai -m space "$index" --destroy
        or return 1
        set -l confirmed (ws_query_spaces workspace_cleanup_after_shortcut "confirm-$uuid")
        or return 1
        printf '%s\n' "$confirmed" | ws_jq -e --arg uuid "$uuid" 'any(.[]; .uuid == $uuid)' >/dev/null
        and begin
            echo "[WARN] empty Space was not removed: $uuid" >&2
            return 1
        end
        printf 'removed_empty_space=%s label=%s\n' "$uuid" "$fields[2]"
        set removed 1
    end
    if not set -q _flag_dry_run; and test "$removed" -eq 1
        set -l final_spaces (ws_query_spaces workspace_cleanup_after_shortcut final)
        or return 1
        set -l focus_index (printf '%s\n' "$final_spaces" | ws_jq -r --arg uuid "$focus_uuid" 'first(.[] | select(.uuid == $uuid) | .index) // empty')
        or return 1
        if test -n "$focus_index"
            set -l final_focus (ws_query_current_space workspace_cleanup_after_shortcut final_focus)
            or return 1
            if test (printf '%s\n' "$final_focus" | ws_jq -r '.uuid') != "$focus_uuid"
                ws_focus_space "$focus_index"
                or return 1
            end
        end
    end
end

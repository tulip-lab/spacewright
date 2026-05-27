function resolve_workspace_external_display --description "Resolve the preferred non-primary workspace display index"
    set -l expected_mode $argv[1]

    switch "$expected_mode"
        case "" wide tall
        case "*"
            echo "[WARN] resolve_workspace_external_display expected mode must be one of: wide, tall" >&2
            return 2
    end

    set -l displays_json (ws_yabai -m query --displays 2>/dev/null)
    if test $status -ne 0 -o -z "$displays_json"
        echo "[WARN] resolve_workspace_external_display: could not query displays" >&2
        return 1
    end

    set -l display_count (echo $displays_json | ws_jq -r 'length')
    if test -z "$display_count" -o "$display_count" -eq 0
        echo "[WARN] resolve_workspace_external_display: no displays available" >&2
        return 1
    end

    if test "$display_count" -eq 1
        echo $displays_json | ws_jq -r '.[0].index'
        return 0
    end

    set -l primary_uuid (get_workspace_primary_display_uuid 2>/dev/null)
    if test -z "$primary_uuid"
        echo "[WARN] resolve_workspace_external_display: workspace primary display UUID is not configured" >&2
        return 1
    end

    set -l mode_filter 'true'
    if test "$expected_mode" = "wide"
        set mode_filter '.frame.w > .frame.h'
    else if test "$expected_mode" = "tall"
        set mode_filter '.frame.h > .frame.w'
    end

    set -l external_display (echo $displays_json | ws_jq -r \
        --arg uuid "$primary_uuid" \
        --arg mode_filter "$mode_filter" '
        first(
            .[]
            | select(.uuid != $uuid)
            | select(if $mode_filter == ".frame.w > .frame.h" then .frame.w > .frame.h
                     elif $mode_filter == ".frame.h > .frame.w" then .frame.h > .frame.w
                     else true end)
            | .index
        )
        // first(.[] | select(.uuid != $uuid) | .index)
        // empty
    ')

    if test -n "$external_display"
        echo $external_display
        return 0
    end

    resolve_workspace_primary_display
end

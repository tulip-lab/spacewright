function resolve_workspace_primary_display --description "Resolve the workspace primary display index"
    set -l displays_json (ws_yabai -m query --displays 2>/dev/null)
    if test $status -ne 0 -o -z "$displays_json"
        echo "[WARN] resolve_workspace_primary_display: could not query displays" >&2
        return 1
    end

    set -l display_count (echo $displays_json | ws_jq -r 'length')
    if test -z "$display_count" -o "$display_count" -eq 0
        echo "[WARN] resolve_workspace_primary_display: no displays available" >&2
        return 1
    end

    if test "$display_count" -eq 1
        echo $displays_json | ws_jq -r '.[0].index'
        return 0
    end

    set -l primary_uuid (get_workspace_primary_display_uuid 2>/dev/null)
    if test -z "$primary_uuid"
        echo "[WARN] resolve_workspace_primary_display: workspace primary display UUID is not configured" >&2
        return 1
    end

    set -l primary_display (echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" '
        first(.[] | select(.uuid==$uuid) | .index) // empty
    ')

    if test -z "$primary_display"
        echo "[WARN] resolve_workspace_primary_display: configured primary display UUID is not present: $primary_uuid" >&2
        return 1
    end

    echo $primary_display
end

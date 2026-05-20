function resolve_external_display --description "Resolve the preferred external display index"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Return the preferred external display index.
    #
    # Behavior:
    #   - Prefer the first display whose UUID differs from the configured
    #     internal display UUID.
    #   - If the display query succeeds but no external display exists, fall
    #     back to the internal display index for single-display operation.
    #   - If the display query fails, return nonzero instead of silently routing
    #     external workspaces to the internal display.
    #   - If the internal UUID is not configured, return nonzero. Set it with
    #     set_internal_display_uuid before using external workspace modes.
    #
    # Usage:
    #   set target_display (resolve_external_display)
    # -------------------------------------------------------------------------

    set -l internal_uuid (get_internal_display_uuid 2>/dev/null)

    if test -z "$internal_uuid"
        echo "[WARN] resolve_external_display: internal display UUID is not configured" >&2
        return 1
    end

    set -l displays_json (ws_yabai -m query --displays 2>/dev/null)
    if test $status -ne 0 -o -z "$displays_json"
        echo "[WARN] resolve_external_display: could not query displays" >&2
        return 1
    end

    set -l external_display (echo $displays_json | ws_jq -r --arg uuid "$internal_uuid" '
        .[]
        | select(.uuid != $uuid)
        | .index
    ' | head -n 1)

    if test -n "$external_display"
        echo $external_display
        return 0
    end

    resolve_internal_display
end

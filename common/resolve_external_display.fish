function resolve_external_display --description "Resolve the preferred external display index, falling back to internal"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Return the preferred external display index.
    #
    # Behavior:
    #   - Prefer the first display whose UUID differs from the configured
    #     internal display UUID.
    #   - If no such display exists, fall back to the internal display index.
    #   - If the internal UUID is not configured, fall back to display 1.
    #
    # Usage:
    #   set target_display (resolve_external_display)
    # -------------------------------------------------------------------------

    set -l internal_uuid (get_internal_display_uuid 2>/dev/null)

    if test -z "$internal_uuid"
        echo 1
        return 0
    end

    set -l external_display (yabai -m query --displays | jq -r --arg uuid "$internal_uuid" '
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
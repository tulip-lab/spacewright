function resolve_internal_display --description "Resolve the internal display index from the configured UUID"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Resolve the internal display index using the configured internal display
    #   UUID.
    #
    # Usage:
    #   set target_display (resolve_internal_display)
    #
    # Fallback:
    #   If no UUID is configured or the display is not found, fall back to 1.
    # -------------------------------------------------------------------------

    set -l internal_uuid (get_internal_display_uuid 2>/dev/null)

    if test -z "$internal_uuid"
        echo 1
        return 0
    end

    resolve_target_display $internal_uuid 1
end
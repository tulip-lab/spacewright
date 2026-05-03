function get_internal_display_uuid --description "Return the configured internal display UUID"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Return the configured machine-specific internal display UUID.
    #
    # Notes:
    #   The value is expected to be stored in the fish universal variable:
    #     WORKSPACE_INTERNAL_DISPLAY_UUID
    #
    #   If the value is missing, this function returns non-zero so callers can
    #   decide how to handle fallback behavior.
    # -------------------------------------------------------------------------

    if test -z "$WORKSPACE_INTERNAL_DISPLAY_UUID"
        return 1
    end

    echo $WORKSPACE_INTERNAL_DISPLAY_UUID
end
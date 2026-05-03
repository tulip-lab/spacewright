function set_internal_display_uuid --description "Persist the internal display UUID for workspace functions"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Store the machine-specific internal display UUID in a fish universal
    #   variable so all workspace modules can reuse it.
    #
    # Usage:
    #   set_internal_display_uuid <display_uuid>
    #
    # Example:
    #   set_internal_display_uuid 37D8832A-2D66-02CA-B9F7-8F30A301B230
    #
    # Notes:
    #   The value is stored in the fish universal variable:
    #     WORKSPACE_INTERNAL_DISPLAY_UUID
    #
    #   This is persistent across future fish sessions for the same user.
    # -------------------------------------------------------------------------

    if test (count $argv) -lt 1
        echo "usage: set_internal_display_uuid <display_uuid>"
        return 1
    end

    set -U WORKSPACE_INTERNAL_DISPLAY_UUID $argv[1]
    echo "WORKSPACE_INTERNAL_DISPLAY_UUID set to: $WORKSPACE_INTERNAL_DISPLAY_UUID"
end
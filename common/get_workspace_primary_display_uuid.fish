function get_workspace_primary_display_uuid --description "Return the configured workspace primary display UUID"
    if test -n "$WORKSPACE_PRIMARY_DISPLAY_UUID"
        echo $WORKSPACE_PRIMARY_DISPLAY_UUID
        return 0
    end

    return 1
end

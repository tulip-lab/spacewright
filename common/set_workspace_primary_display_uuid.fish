function set_workspace_primary_display_uuid --description "Persist the workspace primary display UUID"
    if test (count $argv) -lt 1
        echo "usage: set_workspace_primary_display_uuid <display_uuid>"
        return 1
    end

    set -U WORKSPACE_PRIMARY_DISPLAY_UUID $argv[1]
    echo "WORKSPACE_PRIMARY_DISPLAY_UUID set to: $WORKSPACE_PRIMARY_DISPLAY_UUID"
end

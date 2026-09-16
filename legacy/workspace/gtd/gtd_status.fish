function gtd_status --description "Show display, space and GTD application status"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show a full GTD status snapshot, including:
    #     - displays
    #     - spaces
    #     - GTD-related application windows
    #
    # Notes:
    #   The GTD application list is delegated to `gtd_apps` so the app filter
    #   is defined in one place only.
    # -------------------------------------------------------------------------

    if test "$WORKSPACE_SKIP_STATUS_SNAPSHOT" != "1"
        workspace_status_snapshot
    end

    echo
    echo "===== GTD APPS ====="
    gtd_apps
end

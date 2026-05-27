function office_status --description "Show display, space and office application status"
    if test "$WORKSPACE_SKIP_STATUS_SNAPSHOT" != "1"
        workspace_status_snapshot
    end

    workspace_print_app_status --title "OFFICE APPS" --caller office_status word powerpoint chatgpt
end

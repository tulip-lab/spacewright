function coding_status --description "Show display, space and coding application status"
    if test "$WORKSPACE_SKIP_STATUS_SNAPSHOT" != "1"
        workspace_status_snapshot
    end

    workspace_print_app_status --title "CODING APPS" --caller coding_status code codex warp smartgit flclash thaw
end

function research_status --description "Show display, space and research application status"
    if test "$WORKSPACE_SKIP_STATUS_SNAPSHOT" != "1"
        workspace_status_snapshot
    end

    workspace_print_app_status --title "RESEARCH APPS" --caller research_status zotero chatgpt
end

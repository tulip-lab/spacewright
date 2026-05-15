function research_status --description "Show display, space and research application status"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show a full research status snapshot, including:
    #     - displays
    #     - spaces
    #     - research-related application windows
    #
    # Covered research apps:
    #   - Zotero
    #   - ChatGPT
    # -------------------------------------------------------------------------

    if test "$WORKSPACE_SKIP_STATUS_SNAPSHOT" != "1"
        workspace_status_snapshot
    end

    echo
    echo "===== RESEARCH APPS ====="
    yabai -m query --windows | jq '
        .[]
        | select(
            .app=="Zotero"
            or .app=="ChatGPT"
        )
        | {
            id,
            app,
            title,
            space,
            is_visible: .["is-visible"],
            is_minimized: .["is-minimized"]
        }'
end

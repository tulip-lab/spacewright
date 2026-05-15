function office_status --description "Show display, space and office application status"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show a full office status snapshot, including:
    #     - displays
    #     - spaces
    #     - office-related application windows
    #
    # Covered office apps:
    #   - Microsoft Word
    #   - Microsoft PowerPoint
    #   - ChatGPT
    # -------------------------------------------------------------------------

    if test "$WORKSPACE_SKIP_STATUS_SNAPSHOT" != "1"
        workspace_status_snapshot
    end

    echo
    echo "===== OFFICE APPS ====="
    yabai -m query --windows | jq '
        .[]
        | select(
            .app=="Microsoft Word"
            or .app=="Microsoft PowerPoint"
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

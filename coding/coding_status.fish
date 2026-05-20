function coding_status --description "Show display, space and coding application status"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show a full coding status snapshot, including:
    #     - displays
    #     - spaces
    #     - coding-related application windows
    #
    # Covered coding apps:
    #   - Code
    #   - ChatGPT
    #   - Warp
    #   - SmartGit
    #   - FlClash / Thaw
    #
    # Notes:
    #   Finder is intentionally excluded because it is not currently part of the
    #   rebuilt coding workspace layout set.
    # -------------------------------------------------------------------------

    if test "$WORKSPACE_SKIP_STATUS_SNAPSHOT" != "1"
        workspace_status_snapshot
    end

    echo
    echo "===== CODING APPS ====="
    set -l windows_json (ws_query_windows coding_status status); or return 1

    echo $windows_json | ws_jq '
        .[]
        | select(
            .app=="Code"
            or .app=="ChatGPT"
            or .app=="Warp"
            or .app=="SmartGit"
            or .app=="FlClash"
            or .app=="Thaw"
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

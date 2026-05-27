function gtd_reopen_outlook --description "Lightly reopen Outlook and clear Outlook entries from the workspace bad-window cache"
    set -l outlook_app (workspace_app_name outlook)
    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l windows_json (ws_query_windows gtd_reopen_outlook before); or return 1
    set -l outlook_ids (echo $windows_json | ws_jq -r --arg app "$outlook_app" '
        .[]
        | select(.app==$app)
        | .id
    ')

    for window_id in $outlook_ids
        if string match -qr '^[0-9]+$' -- "$window_id"
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
        end
    end

    osascript -e "tell application \"$outlook_app\" to activate" -e "tell application \"$outlook_app\" to reopen" >/dev/null 2>&1
    or open -a "$outlook_app" >/dev/null 2>&1

    sleep 1

    set windows_json (ws_query_windows gtd_reopen_outlook after); or return 1

    echo "===== OUTLOOK WINDOWS ====="
    echo $windows_json | ws_jq --arg app "$outlook_app" '
        .[]
        | select(.app==$app)
        | {
            id,
            title,
            space,
            display,
            is_visible: .["is-visible"],
            is_minimized: .["is-minimized"],
            can_move: .["can-move"],
            can_resize: .["can-resize"],
            has_ax_reference: .["has-ax-reference"],
            role,
            subrole
        }'
end

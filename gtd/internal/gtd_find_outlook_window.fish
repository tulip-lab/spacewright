function gtd_find_outlook_window --description "Find a movable Microsoft Outlook window, activating Outlook once if needed"
    set -l caller $argv[1]

    if test -z "$caller"
        set caller gtd_meeting
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l windows_json (ws_query_windows "$caller" outlook); or return 1
    set -l out (echo $windows_json | jq -r '
        .[]
        | select(.app=="Microsoft Outlook")
        | select(.["is-minimized"]==false)
        | select(.["can-move"]==true)
        | .id
    ' | head -n 1)

    if test -n "$out"
        rm -f "$bad_window_dir/$out" 2>/dev/null
        echo $out
        return 0
    end

    set -l outlook_present (echo $windows_json | jq -r '
        .[]
        | select(.app=="Microsoft Outlook")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -z "$outlook_present"
        return 0
    end

    osascript -e 'tell application "Microsoft Outlook" to activate' -e 'tell application "Microsoft Outlook" to reopen' >/dev/null 2>&1
    or open -a "Microsoft Outlook" >/dev/null 2>&1

    sleep 0.8

    set windows_json (ws_query_windows "$caller" outlook_refresh); or return 1
    set out (echo $windows_json | jq -r '
        .[]
        | select(.app=="Microsoft Outlook")
        | select(.["is-minimized"]==false)
        | select(.["can-move"]==true)
        | .id
    ' | head -n 1)

    if test -n "$out"
        rm -f "$bad_window_dir/$out" 2>/dev/null
        echo $out
        return 0
    end

    echo "[WARN] $caller found Microsoft Outlook, but yabai did not expose a movable Outlook window" >&2
    return 2
end

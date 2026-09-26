function __gtd_support_clear_bad_dia_windows --description "Clear bad-window cache entries for movable Dia windows"
    for wid in $argv
        rm -f /tmp/workspace-ws-window-bad/$wid 2>/dev/null
    end
end

function __gtd_support_refresh_dia_app --description "Activate Dia briefly before re-querying yabai windows"
    set -l dia_app $argv[1]

    if test -z "$dia_app"
        return 1
    end

    perl -e 'alarm shift; exec @ARGV' 2 open -a "$dia_app" >/dev/null 2>&1
end

function __gtd_support_filter_dia_window_json --description "Exclude Dia accessibility helpers from window selection"
    ws_jq '[.[] | select((.role // "") == "" or .role == "AXWindow")]'
end

function gtd_support_find_dia_windows --description "Find all movable Dia windows for a GTD support workspace"
    set -l caller $argv[1]

    if test -z "$caller"
        set caller gtd_support
    end

    set -l windows_json
    read -lz windows_json

    if test -z "$windows_json"
        return 1
    end

    set -l dia_app (workspace_app_name dia)
    set -l dia_window_json (printf '%s\n' "$windows_json" | __gtd_support_filter_dia_window_json)
    or return 1
    set -l dia_present (printf '%s\n' "$dia_window_json" | ws_find_windows "$dia_app" --not-native-fullscreen)
    set -l dia_windows (printf '%s\n' "$dia_window_json" | ws_find_windows "$dia_app" --movable --not-native-fullscreen)

    if test (count $dia_present) -eq 0
        return 0
    end

    if test (count $dia_windows) -eq (count $dia_present)
        __gtd_support_clear_bad_dia_windows $dia_windows
        printf "%s\n" $dia_windows
        return 0
    end

    __gtd_support_refresh_dia_app "$dia_app"
    sleep 0.4

    set windows_json (ws_query_windows "$caller" dia_refresh)
    or return 1

    set dia_window_json (printf '%s\n' "$windows_json" | __gtd_support_filter_dia_window_json)
    or return 1
    set dia_present (printf '%s\n' "$dia_window_json" | ws_find_windows "$dia_app" --not-native-fullscreen)
    set dia_windows (printf '%s\n' "$dia_window_json" | ws_find_windows "$dia_app" --movable --not-native-fullscreen)

    if test (count $dia_present) -gt 0 -a (count $dia_windows) -eq (count $dia_present)
        __gtd_support_clear_bad_dia_windows $dia_windows
        printf "%s\n" $dia_windows
        return 0
    end

    ws_recover_yabai_once "$caller" "found Dia, but yabai did not expose a movable Dia window"
    or begin
        echo "[HINT] If Dia stays non-movable, run: yabai --restart-service" >&2
        return 1
    end

    set windows_json (ws_query_windows "$caller" dia_yabai_restart)
    or return 1

    set dia_window_json (printf '%s\n' "$windows_json" | __gtd_support_filter_dia_window_json)
    or return 1
    set dia_present (printf '%s\n' "$dia_window_json" | ws_find_windows "$dia_app" --not-native-fullscreen)
    set dia_windows (printf '%s\n' "$dia_window_json" | ws_find_windows "$dia_app" --movable --not-native-fullscreen)

    if test (count $dia_present) -gt 0 -a (count $dia_windows) -eq (count $dia_present)
        __gtd_support_clear_bad_dia_windows $dia_windows
        printf "%s\n" $dia_windows
        return 0
    end

    echo "[WARN] $caller found Dia, but yabai still did not expose every eligible Dia window as movable after restarting yabai" >&2
    echo "[HINT] If Dia stays non-movable, run: yabai --restart-service" >&2
    return 1
end

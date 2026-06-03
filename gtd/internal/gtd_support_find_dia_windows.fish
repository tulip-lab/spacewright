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
    set -l dia_windows (printf '%s\n' "$windows_json" | ws_find_windows "$dia_app" --movable --not-native-fullscreen)

    if test (count $dia_windows) -gt 0
        for wid in $dia_windows
            rm -f /tmp/workspace-ws-window-bad/$wid 2>/dev/null
        end

        printf "%s\n" $dia_windows
        return 0
    end

    set -l dia_present (printf '%s\n' "$windows_json" | ws_find_windows "$dia_app" --not-native-fullscreen)
    if test (count $dia_present) -eq 0
        return 0
    end

    perl -e 'alarm shift; exec @ARGV' 2 open -a "$dia_app" >/dev/null 2>&1
    sleep 0.4

    set windows_json (ws_query_windows "$caller" dia_refresh)
    or return 1

    set dia_windows (printf '%s\n' "$windows_json" | ws_find_windows "$dia_app" --movable --not-native-fullscreen)

    if test (count $dia_windows) -gt 0
        for wid in $dia_windows
            rm -f /tmp/workspace-ws-window-bad/$wid 2>/dev/null
        end

        printf "%s\n" $dia_windows
        return 0
    end

    echo "[WARN] $caller found Dia, but yabai did not expose a movable Dia window" >&2
    echo "[HINT] If Dia stays non-movable, run: yabai --restart-service" >&2
    return 1
end

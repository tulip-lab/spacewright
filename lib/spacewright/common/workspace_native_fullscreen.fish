function workspace_normalize_native_fullscreen_windows --description "Exit native fullscreen for selected workspace apps and return a refreshed window snapshot"
    argparse 'caller=' 'app=' -- $argv
    or return 1

    set -l caller workspace_normalize_native_fullscreen_windows
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l app_names
    if set -q _flag_app
        set -a app_names $_flag_app
    end
    for app_key in $argv
        set -a app_names (workspace_app_names $app_key)
        or return 1
    end

    if test (count $app_names) -eq 0
        echo "usage: workspace_normalize_native_fullscreen_windows [--caller <name>] [--app <name>] [app-key ...]" >&2
        return 2
    end

    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        return 1
    end

    set -l apps_json (printf '%s\n' $app_names | ws_jq -R . | ws_jq -s unique)
    or return 1
    set -l fullscreen_ids (printf '%s\n' "$windows_json" | ws_jq -r --argjson apps "$apps_json" '
        .[]
        | select(.app as $app | $apps | index($app))
        | select(.["is-minimized"]==false)
        | select(.["is-native-fullscreen"]==true)
        | .id
    ')
    or return 1

    if test (count $fullscreen_ids) -eq 0
        printf '%s\n' "$windows_json"
        return 0
    end

    workspace_debug_step "$caller" native-fullscreen-exit count=(count $fullscreen_ids)
    for wid in $fullscreen_ids
        rm -f /tmp/workspace-ws-window-bad/$wid 2>/dev/null
        ws_window $wid --toggle native-fullscreen
    end

    set -l fullscreen_ids_json (printf '%s\n' $fullscreen_ids | ws_jq -R 'tonumber' | ws_jq -s .)
    or return 1
    for attempt in (seq 1 12)
        sleep 0.25
        set windows_json (ws_query_windows "$caller" native_fullscreen_$attempt)
        or continue

        if printf '%s\n' "$windows_json" | ws_jq -e --argjson ids "$fullscreen_ids_json" '
            . as $windows
            | all($ids[]; . as $id | any($windows[]; .id==$id and .["is-native-fullscreen"]!=true))
        ' >/dev/null 2>&1
            printf '%s\n' "$windows_json"
            return 0
        end
    end

    echo "[WARN] $caller could not confirm native-fullscreen exit for windows: "(string join , -- $fullscreen_ids) >&2
    return 1
end

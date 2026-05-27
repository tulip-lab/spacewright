function gtd_find_teams_window --description "Find a movable Microsoft Teams window, clearing recovered bad-window cache entries"
    set -l caller $argv[1]
    set -l target_space ""
    set -l mode ""
    set -l target_only 0

    if test -z "$caller"
        set caller gtd_meeting
    end

    for arg in $argv[2..-1]
        if test "$arg" = "--no-refresh"
            set mode --no-refresh
        else if test "$arg" = "--target-only"
            set target_only 1
        else if test -z "$target_space"
            set target_space $arg
        end
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l teams

    if test -n "$target_space"
        workspace_debug_step $caller teams-target-query
        set -l windows_json (ws_query_windows "$caller" teams_target); or return 1
        set teams (echo $windows_json | ws_jq -r \
            --arg target_space "$target_space" '
            first(
                .[]
                | select(.app=="Microsoft Teams" or .app=="MSTeams")
                | select(.["is-minimized"]==false)
                | select(.space==($target_space | tonumber))
                | select(.["can-move"]==true)
                | select((.title // "" | ascii_downcase) as $title
                    | ($title | contains("meeting") | not)
                    and ($title | contains("video") | not)
                    and ($title | contains("call") | not)
                    and ($title | contains("share") | not)
                    and ($title | contains("screen") | not)
                    and ($title | contains("mini") | not))
                | .id
            ) // empty
        ')

        if test -n "$teams"
            workspace_debug_step $caller teams-target-found $teams
            rm -f "$bad_window_dir/$teams" 2>/dev/null
            echo $teams
            return 0
        end

        if test "$target_only" -eq 1
            return 0
        end
    end

    workspace_debug_step $caller teams-any-query
    set -l windows_json (ws_query_windows "$caller" teams_any); or return 1
    set teams (echo $windows_json | ws_jq -r '
        first(
            .[]
            | select(.app=="Microsoft Teams" or .app=="MSTeams")
            | select(.["is-minimized"]==false)
            | select(.["can-move"]==true)
            | select((.title // "" | ascii_downcase) as $title
                | ($title | contains("meeting") | not)
                and ($title | contains("video") | not)
                and ($title | contains("call") | not)
                and ($title | contains("share") | not)
                and ($title | contains("screen") | not)
                and ($title | contains("mini") | not))
            | .id
        ) // empty
    ')

    if test -n "$teams"
        workspace_debug_step $caller teams-any-found $teams
        rm -f "$bad_window_dir/$teams" 2>/dev/null
        echo $teams
        return 0
    end

    if test "$mode" = "--no-refresh"
        return 0
    end

    set -l teams_present (echo $windows_json | ws_jq -r '
        first(
            .[]
            | select(.app=="Microsoft Teams" or .app=="MSTeams")
            | select(.["is-minimized"]==false)
            | .id
        ) // empty
    ')

    if test -z "$teams_present"
        return 0
    end

    workspace_debug_step $caller teams-refresh
    perl -e 'alarm shift; exec @ARGV' 2 open -a "Microsoft Teams" >/dev/null 2>&1
    sleep 0.6

    workspace_debug_step $caller teams-after-refresh-query
    set windows_json (ws_query_windows "$caller" teams_after_refresh); or return 1
    set teams (echo $windows_json | ws_jq -r '
        first(
            .[]
            | select(.app=="Microsoft Teams" or .app=="MSTeams")
            | select(.["is-minimized"]==false)
            | select(.["can-move"]==true)
            | select((.title // "" | ascii_downcase) as $title
                | ($title | contains("meeting") | not)
                and ($title | contains("video") | not)
                and ($title | contains("call") | not)
                and ($title | contains("share") | not)
                and ($title | contains("screen") | not)
                and ($title | contains("mini") | not))
            | .id
        ) // empty
    ')

    if test -n "$teams"
        workspace_debug_step $caller teams-after-refresh-found $teams
        rm -f "$bad_window_dir/$teams" 2>/dev/null
        echo $teams
        return 0
    end

    workspace_debug_step $caller teams-refresh-unmovable
    echo "[WARN] $caller found Microsoft Teams, but yabai did not expose a movable Teams window" >&2
    return 2
end

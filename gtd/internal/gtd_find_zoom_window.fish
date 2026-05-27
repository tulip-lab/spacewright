function gtd_find_zoom_window --description "Find a movable Zoom main window, clearing recovered bad-window cache entries"
    set -l caller $argv[1]
    set -l target_space ""
    set -l target_only 0

    if test -z "$caller"
        set caller gtd_meeting
    end

    for arg in $argv[2..-1]
        if test "$arg" = "--target-only"
            set target_only 1
        else if test "$arg" != "--no-refresh" -a -z "$target_space"
            set target_space $arg
        end
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l zoom

    if test -n "$target_space"
        workspace_debug_step $caller zoom-target-query
        set -l windows_json (ws_query_windows "$caller" zoom_target); or return 1
        set zoom (echo $windows_json | ws_jq -r \
            --arg target_space "$target_space" '
            first(
                .[]
                | select(.app=="zoom.us")
                | select(.["is-minimized"]==false)
                | select(.space==($target_space | tonumber))
                | select(.["can-move"]==true)
                | select((.title // "" | ascii_downcase) as $title
                    | ($title | contains("meeting") | not)
                    and ($title | contains("video") | not)
                    and ($title | contains("share") | not)
                    and ($title | contains("screen") | not)
                    and ($title | contains("mini") | not))
                | .id
            ) // empty
        ')

        if test -n "$zoom"
            workspace_debug_step $caller zoom-target-found $zoom
            rm -f "$bad_window_dir/$zoom" 2>/dev/null
            echo $zoom
            return 0
        end

        if test "$target_only" -eq 1
            return 0
        end
    end

    workspace_debug_step $caller zoom-any-query
    set -l windows_json (ws_query_windows "$caller" zoom_any); or return 1
    set zoom (echo $windows_json | ws_jq -r '
        first(
            .[]
            | select(.app=="zoom.us")
            | select(.["is-minimized"]==false)
            | select(.["can-move"]==true)
            | select((.title // "" | ascii_downcase) as $title
                | ($title | contains("meeting") | not)
                and ($title | contains("video") | not)
                and ($title | contains("share") | not)
                and ($title | contains("screen") | not)
                and ($title | contains("mini") | not))
            | .id
        ) // empty
    ')

    if test -n "$zoom"
        workspace_debug_step $caller zoom-any-found $zoom
        rm -f "$bad_window_dir/$zoom" 2>/dev/null
        echo $zoom
    end
end

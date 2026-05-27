function gtd_find_meeting_window --description "Find a movable GTD meeting helper window by workspace app key"
    set -l app_key $argv[1]
    set -l debug_name $argv[2]
    set -l warning_name $argv[3]
    set -l refresh_policy $argv[4]
    set -l exclude_titles (string split ',' -- $argv[5])
    set -l caller $argv[6]
    set -l target_space ""
    set -l no_refresh 0
    set -l target_only 0

    if test -z "$caller"
        set caller gtd_meeting
    end

    for arg in $argv[7..-1]
        if test "$arg" = "--no-refresh"
            set no_refresh 1
        else if test "$arg" = "--target-only"
            set target_only 1
        else if test -z "$target_space"
            set target_space $arg
        end
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l apps_json (workspace_app_names_json $app_key)
    or return 1
    set -l app_name (workspace_app_name $app_key)
    or return 1
    set -l exclude_titles_json (printf "%s\n" $exclude_titles | ws_jq -R . | ws_jq -s .)

    set -l candidate_filter '
        first(
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.["is-minimized"]==false)
            | select(($target_space=="") or (.space==($target_space | tonumber)))
            | select(.["can-move"]==true)
            | select((.title // "" | ascii_downcase) as $title
                | (any($exclude_titles[]; . as $needle | $title | contains($needle | ascii_downcase)) | not))
            | .id
        ) // empty
    '

    if test -n "$target_space"
        workspace_debug_step $caller "$debug_name-target-query"
        set -l windows_json (ws_query_windows "$caller" "$debug_name"_target); or return 1
        set -l window_id (echo $windows_json | ws_jq -r \
            --argjson apps "$apps_json" \
            --argjson exclude_titles "$exclude_titles_json" \
            --arg target_space "$target_space" \
            "$candidate_filter")

        if test -n "$window_id"
            workspace_debug_step $caller "$debug_name-target-found" $window_id
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
            echo $window_id
            return 0
        end

        if test "$target_only" -eq 1
            return 0
        end
    end

    workspace_debug_step $caller "$debug_name-any-query"
    set -l windows_json (ws_query_windows "$caller" "$debug_name"_any); or return 1
    set -l window_id (echo $windows_json | ws_jq -r \
        --argjson apps "$apps_json" \
        --argjson exclude_titles "$exclude_titles_json" \
        --arg target_space "" \
        "$candidate_filter")

    if test -n "$window_id"
        workspace_debug_step $caller "$debug_name-any-found" $window_id
        rm -f "$bad_window_dir/$window_id" 2>/dev/null
        echo $window_id
        return 0
    end

    if test "$refresh_policy" != "refresh" -o "$no_refresh" -eq 1
        return 0
    end

    set -l present_id (echo $windows_json | ws_jq -r --argjson apps "$apps_json" '
        first(
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.["is-minimized"]==false)
            | .id
        ) // empty
    ')

    if test -z "$present_id"
        return 0
    end

    workspace_debug_step $caller "$debug_name-refresh"
    perl -e 'alarm shift; exec @ARGV' 2 open -a "$app_name" >/dev/null 2>&1
    sleep 0.6

    workspace_debug_step $caller "$debug_name-after-refresh-query"
    set windows_json (ws_query_windows "$caller" "$debug_name"_after_refresh); or return 1
    set window_id (echo $windows_json | ws_jq -r \
        --argjson apps "$apps_json" \
        --argjson exclude_titles "$exclude_titles_json" \
        --arg target_space "" \
        "$candidate_filter")

    if test -n "$window_id"
        workspace_debug_step $caller "$debug_name-after-refresh-found" $window_id
        rm -f "$bad_window_dir/$window_id" 2>/dev/null
        echo $window_id
        return 0
    end

    workspace_debug_step $caller "$debug_name-refresh-unmovable"
    echo "[WARN] $caller found $warning_name, but yabai did not expose a movable $warning_name window" >&2
    return 2
end

function gtd_find_zoom_window --description "Find a movable Zoom main window, clearing recovered bad-window cache entries"
    gtd_find_meeting_window zoom zoom Zoom none meeting,video,share,screen,mini $argv
end

function gtd_find_teams_window --description "Find a movable Microsoft Teams window, clearing recovered bad-window cache entries"
    gtd_find_meeting_window teams teams "Microsoft Teams" refresh meeting,video,call,share,screen,mini $argv
end

function workspace_select_app_window --description "Select a window id for an app from yabai windows JSON on stdin"
    argparse 'app=' 'space=' movable visible -- $argv
    or return 1

    if not set -q _flag_app
        echo "usage: workspace_select_app_window --app <app-name> [--space <space>] [--movable] [--visible]" >&2
        return 1
    end

    set -l movable 0
    set -l visible 0
    set -l target_space ""

    if set -q _flag_movable
        set movable 1
    end

    if set -q _flag_visible
        set visible 1
    end

    if set -q _flag_space
        set target_space $_flag_space
    end

    if test "$WORKSPACE_DEBUG_SELECT" = "1"
        workspace_debug_step workspace_select_app_window read-start app=$_flag_app
    end

    set -l windows_json
    read -lz windows_json

    if test "$WORKSPACE_DEBUG_SELECT" = "1"
        workspace_debug_step workspace_select_app_window read-done app=$_flag_app bytes=(string length -- "$windows_json")
        workspace_debug_step workspace_select_app_window jq-start app=$_flag_app
    end

    set -l window_id (echo $windows_json | ws_jq -r \
        --arg app "$_flag_app" \
        --arg target_space "$target_space" \
        --arg movable "$movable" \
        --arg visible "$visible" \
        '
        first(
            .[]
            | select(.app==$app)
            | select(.["is-minimized"]==false)
            | select(($target_space=="") or (.space==($target_space | tonumber)))
            | select(($movable!="1") or (.["can-move"]==true))
            | select(($visible!="1") or (.["is-visible"]==true))
            | .id
        ) // empty
        '
    )
    set -l jq_status $status

    if test "$WORKSPACE_DEBUG_SELECT" = "1"
        workspace_debug_step workspace_select_app_window jq-done app=$_flag_app status=$jq_status window=$window_id
    end

    if test "$jq_status" -ne 0
        return $jq_status
    end

    if test -n "$window_id"
        echo $window_id
    end
end

function workspace_refresh_app_window --description "Find an app window, activating the app once if needed"
    argparse 'app=' 'caller=' 'space=' movable visible -- $argv
    or return 1

    if not set -q _flag_app
        echo "usage: workspace_refresh_app_window --app <app-name> [--caller <name>] [--space <space>] [--movable] [--visible]" >&2
        return 1
    end

    set -l caller workspace_refresh_app_window
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l selector_args --app "$_flag_app"

    if set -q _flag_space
        set -a selector_args --space $_flag_space
    end

    if set -q _flag_movable
        set -a selector_args --movable
    end

    if set -q _flag_visible
        set -a selector_args --visible
    end

    workspace_debug_step $caller refresh-$_flag_app-query-initial
    set -l windows_json (ws_query_windows "$caller" app_refresh_initial); or return 1
    set -l window_id (echo $windows_json | workspace_select_app_window $selector_args)
    if test $status -ne 0
        return 1
    end

    if test -n "$window_id"
        workspace_debug_step $caller refresh-$_flag_app-found-initial $window_id
        echo $window_id
        return 0
    end

    set -l app_present (echo $windows_json | workspace_select_app_window --app "$_flag_app")
    if test $status -ne 0
        return 1
    end

    if test -z "$app_present"
        workspace_debug_step $caller refresh-$_flag_app-not-present
        return 0
    end

    workspace_debug_step $caller refresh-$_flag_app-open
    perl -e 'alarm shift; exec @ARGV' 2 open -a "$_flag_app" >/dev/null 2>&1
    sleep 0.4

    workspace_debug_step $caller refresh-$_flag_app-query-after-open
    set windows_json (ws_query_windows "$caller" app_refresh_after_open); or return 1
    set window_id (echo $windows_json | workspace_select_app_window $selector_args)
    if test $status -ne 0
        return 1
    end

    if test -n "$window_id"
        workspace_debug_step $caller refresh-$_flag_app-found-after-open $window_id
        echo $window_id
        return 0
    end

    workspace_debug_step $caller refresh-$_flag_app-unavailable
    return 2
end

function workspace_find_app_window --description "Find a movable app window, activating the app once if needed"
    argparse 'app=' 'caller=' 'space=' 'attempts=' 'wait=' no-refresh target-only visible quiet-unmovable -- $argv
    or return 1

    if not set -q _flag_app
        echo "usage: workspace_find_app_window --app <app-name> [--caller <name>] [--space <space>] [--no-refresh] [--target-only] [--visible]" >&2
        return 1
    end

    set -l caller workspace_find_app_window
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l attempts 4
    if set -q _flag_attempts
        set attempts $_flag_attempts
    end

    set -l wait_seconds 0.5
    if set -q _flag_wait
        set wait_seconds $_flag_wait
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l selector_args --app "$_flag_app" --movable
    set -l app_key (string replace -ra '[^A-Za-z0-9]+' '_' -- "$_flag_app")

    if set -q _flag_visible
        set -a selector_args --visible
    end

    if set -q _flag_space
        workspace_debug_step $caller find-$app_key-target-query
        set -l phase find_{$app_key}_target
        set -l windows_json (ws_query_windows "$caller" $phase); or return 1
        set -l target_selector_args $selector_args --space $_flag_space
        set -l window_id (echo $windows_json | workspace_select_app_window $target_selector_args)

        if test -n "$window_id"
            workspace_debug_step $caller find-$app_key-target-found $window_id
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
            echo $window_id
            return 0
        end

        if set -q _flag_target_only
            workspace_debug_step $caller find-$app_key-target-missing
            return 0
        end
    end

    if set -q _flag_no_refresh
        workspace_debug_step $caller find-$app_key-any-query
        set -l phase find_{$app_key}_any
        set -l windows_json (ws_query_windows "$caller" $phase); or return 1
        set -l window_id (echo $windows_json | workspace_select_app_window $selector_args)

        if test -n "$window_id"
            workspace_debug_step $caller find-$app_key-any-found $window_id
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
            echo $window_id
        end

        return 0
    end

    workspace_debug_step $caller find-$app_key-refresh-query-initial
    set -l phase find_{$app_key}_refresh_initial
    set -l windows_json (ws_query_windows "$caller" $phase); or return 1
    set -l window_id (echo $windows_json | workspace_select_app_window $selector_args)

    if test -n "$window_id"
        workspace_debug_step $caller find-$app_key-refresh-found-initial $window_id
        rm -f "$bad_window_dir/$window_id" 2>/dev/null
        echo $window_id
        return 0
    end

    set -l app_present (echo $windows_json | workspace_select_app_window --app "$_flag_app")
    if test -z "$app_present"
        workspace_debug_step $caller find-$app_key-not-present
        return 0
    end

    set -l app_present_space (echo $windows_json | ws_jq -r --arg app "$_flag_app" '
        first(
            .[]
            | select(.app==$app)
            | select(.["is-minimized"]==false)
            | .space
        ) // empty
    ')

    if test -n "$app_present_space"
        workspace_debug_step $caller find-$app_key-focus-present-space $app_present_space
        ws_focus_space $app_present_space >/dev/null 2>&1
        sleep 0.2

        set phase find_{$app_key}_after_present_space_focus
        set windows_json (ws_query_windows "$caller" $phase); or return 1
        set window_id (echo $windows_json | workspace_select_app_window $selector_args)

        if test -n "$window_id"
            workspace_debug_step $caller find-$app_key-found-after-present-space-focus $window_id
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
            echo $window_id
            return 0
        end
    end

    workspace_debug_step $caller find-$app_key-activate
    perl -e 'alarm shift; exec @ARGV' 2 open -a "$_flag_app" >/dev/null 2>&1

    for attempt in (seq 1 $attempts)
        sleep $wait_seconds
        workspace_debug_step $caller find-$app_key-refresh-query-after-activate-$attempt
        set phase find_{$app_key}_refresh_after_activate_$attempt
        set windows_json (ws_query_windows "$caller" $phase); or return 1
        set window_id (echo $windows_json | workspace_select_app_window $selector_args)

        if test -n "$window_id"
            workspace_debug_step $caller find-$app_key-refresh-found-after-activate $window_id
            rm -f "$bad_window_dir/$window_id" 2>/dev/null
            echo $window_id
            return 0
        end
    end

    workspace_debug_step $caller find-$app_key-refresh-unmovable
    if not set -q _flag_quiet_unmovable
        echo "[WARN] $caller found $_flag_app, but yabai did not expose a movable $_flag_app window" >&2
    end
    return 2
end

function workspace_find_app_key_window --description "Find a movable app window using all registered names for an app key"
    argparse 'app-key=' 'caller=' 'space=' 'attempts=' 'wait=' no-refresh target-only visible quiet-unmovable -- $argv
    or return 1

    if not set -q _flag_app_key
        echo "usage: workspace_find_app_key_window --app-key <key> [--caller <name>] [--space <space>] [--no-refresh] [--target-only] [--visible]" >&2
        return 1
    end

    set -l caller workspace_find_app_key_window
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l app_names (workspace_app_names $_flag_app_key)
    or return 1

    set -l attempts 4
    if set -q _flag_attempts
        set attempts $_flag_attempts
    end

    set -l wait_seconds 0.5
    if set -q _flag_wait
        set wait_seconds $_flag_wait
    end

    set -l saw_unmovable 0

    for app_name in $app_names
        set -l find_args --app "$app_name" --caller "$caller"

        if set -q _flag_space
            set -a find_args --space $_flag_space
        end

        if set -q _flag_attempts
            set -a find_args --attempts $_flag_attempts
        end

        if set -q _flag_wait
            set -a find_args --wait $_flag_wait
        end

        if set -q _flag_no_refresh
            set -a find_args --no-refresh
        end

        if set -q _flag_target_only
            set -a find_args --target-only
        end

        if set -q _flag_visible
            set -a find_args --visible
        end

        if set -q _flag_quiet_unmovable
            set -a find_args --quiet-unmovable
        end

        set -l window_id (workspace_find_app_window $find_args)
        set -l find_status $status

        if test "$find_status" -eq 1
            return 1
        end

        if test -n "$window_id"
            echo $window_id
            return 0
        end

        if test "$find_status" -eq 2
            set saw_unmovable 1
        end
    end

    if test "$saw_unmovable" -eq 1
        if not set -q _flag_no_refresh
            workspace_debug_step $caller find-$_flag_app_key-activate-canonical $app_names[1]
            perl -e 'alarm shift; exec @ARGV' 2 open -a "$app_names[1]" >/dev/null 2>&1

            for attempt in (seq 1 $attempts)
                sleep $wait_seconds

                for app_name in $app_names
                    set -l retry_find_args --app "$app_name" --caller "$caller" --no-refresh

                    if set -q _flag_space
                        set -a retry_find_args --space $_flag_space
                    end

                    if set -q _flag_visible
                        set -a retry_find_args --visible
                    end

                    if set -q _flag_target_only
                        set -a retry_find_args --target-only
                    end

                    if set -q _flag_quiet_unmovable
                        set -a retry_find_args --quiet-unmovable
                    end

                    set -l window_id (workspace_find_app_window $retry_find_args)
                    set -l find_status $status

                    if test "$find_status" -eq 1
                        return 1
                    end

                    if test -n "$window_id"
                        echo $window_id
                        return 0
                    end
                end
            end
        end

        for app_name in $app_names
            set -l final_find_args --app "$app_name" --caller "$caller" --no-refresh

            if set -q _flag_space
                set -a final_find_args --space $_flag_space
            end

            if set -q _flag_visible
                set -a final_find_args --visible
            end

            if set -q _flag_target_only
                set -a final_find_args --target-only
            end

            if set -q _flag_quiet_unmovable
                set -a final_find_args --quiet-unmovable
            end

            set -l window_id (workspace_find_app_window $final_find_args)
            set -l find_status $status

            if test "$find_status" -eq 1
                return 1
            end

            if test -n "$window_id"
                echo $window_id
                return 0
            end
        end

        return 2
    end

    return 0
end

function workspace_app_key_window_info --description "Return first non-minimized app-key window metadata from yabai window JSON on stdin"
    argparse 'app-key=' movable unmovable -- $argv
    or return 1

    if not set -q _flag_app_key
        echo "usage: workspace_app_key_window_info --app-key <key> [--movable|--unmovable]" >&2
        return 2
    end

    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        return 1
    end

    set -l apps_json (workspace_app_names_json $_flag_app_key)
    or return 1

    set -l movable_filter ""
    if set -q _flag_movable
        set movable_filter movable
    else if set -q _flag_unmovable
        set movable_filter unmovable
    end

    echo $windows_json | ws_jq -r --argjson apps "$apps_json" --arg movable_filter "$movable_filter" '
        first(
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.["is-minimized"]==false)
            | select(
                if $movable_filter == "movable" then
                    .["can-move"]==true
                elif $movable_filter == "unmovable" then
                    .["can-move"]!=true
                else
                    true
                end
            )
            | [.id, .space, .display, .["can-move"]]
            | @tsv
        ) // empty
    '
end

function workspace_app_key_windows --description "Return matching app-key window ids from yabai window JSON"
    argparse 'app-key=' 'space=' 'not-space=' movable unmovable visible nonempty-title not-native-fullscreen -- $argv
    or return 1

    if not set -q _flag_app_key
        echo "usage: workspace_app_key_windows --app-key <key> [--space <space>] [--not-space <space>] [--movable|--unmovable] [--visible] [--nonempty-title] [--not-native-fullscreen]" >&2
        return 2
    end

    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        return 1
    end

    set -l apps_json (workspace_app_names_json $_flag_app_key)
    or return 1

    set -l space "$_flag_space"
    set -l not_space "$_flag_not_space"
    set -l movable_filter ""
    set -l visible 0
    set -l nonempty_title 0
    set -l not_native_fullscreen 0

    if set -q _flag_movable
        set movable_filter movable
    else if set -q _flag_unmovable
        set movable_filter unmovable
    end

    if set -q _flag_visible
        set visible 1
    end

    if set -q _flag_nonempty_title
        set nonempty_title 1
    end

    if set -q _flag_not_native_fullscreen
        set not_native_fullscreen 1
    end

    echo $windows_json | ws_jq -r \
        --argjson apps "$apps_json" \
        --arg space "$space" \
        --arg not_space "$not_space" \
        --arg movable_filter "$movable_filter" \
        --arg visible "$visible" \
        --arg nonempty_title "$nonempty_title" \
        --arg not_native_fullscreen "$not_native_fullscreen" '
        .[]
        | select(.app as $app | $apps | index($app))
        | select(.["is-minimized"]==false)
        | select(($visible!="1") or (.["is-visible"]==true))
        | select(($nonempty_title!="1") or (.title != null and .title != ""))
        | select(($not_native_fullscreen!="1") or (.["is-native-fullscreen"]!=true))
        | select(
            if $movable_filter == "movable" then
                .["can-move"]==true
            elif $movable_filter == "unmovable" then
                .["can-move"]!=true
            else
                true
            end
        )
        | select(($space=="") or (.space==($space | tonumber)))
        | select(($not_space=="") or (.space!=($not_space | tonumber)))
        | .id
    '
end

function workspace_app_key_space_fallback_info --description "Return a present app-key window id, space and display for space fallback"
    argparse 'app-key=' 'caller=' 'phase=' -- $argv
    or return 1

    if not set -q _flag_app_key
        echo "usage: workspace_app_key_space_fallback_info --app-key <key> [--caller <name>] [--phase <query-phase>]" >&2
        return 2
    end

    set -l caller workspace_app_key_space_fallback_info
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l phase app_key_space_fallback
    if set -q _flag_phase
        set phase $_flag_phase
    end

    set -l apps_json (workspace_app_names_json $_flag_app_key)
    or return 1

    set -l windows_json (ws_query_windows $caller $phase)
    or return 1

    set -l fallback_info (echo $windows_json | ws_jq -r --argjson apps "$apps_json" '
        first(
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.["is-minimized"]==false)
            | [.id, .space, .display]
            | @tsv
        ) // empty
    ')
    set -l jq_status $status

    if test "$jq_status" -ne 0
        return $jq_status
    end

    if test -z "$fallback_info"
        return 2
    end

    set -l fallback_parts (string split \t -- "$fallback_info")
    set -l window_id $fallback_parts[1]
    set -l target_space $fallback_parts[2]
    set -l source_display $fallback_parts[3]

    if test -z "$window_id" -o -z "$target_space" -o -z "$source_display"
        return 2
    end

    printf "%s\t%s\t%s\n" "$window_id" "$target_space" "$source_display"
end

function workspace_apply_app_key_grid_bounds --description "Apply a grid by setting scriptable app window bounds"
    argparse 'app-key=' 'display=' 'grid=' 'caller=' all-windows -- $argv
    or return 1

    if not set -q _flag_app_key; or not set -q _flag_display; or not set -q _flag_grid
        echo "usage: workspace_apply_app_key_grid_bounds --app-key <key> --display <display-index> --grid <rows:cols:x:y:w:h> [--caller <name>] [--all-windows]" >&2
        return 2
    end

    set -l caller workspace_apply_app_key_grid_bounds
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l grid_parts (string split : -- $_flag_grid)
    if test (count $grid_parts) -ne 6
        echo "[WARN] $caller invalid grid for AppleScript bounds fallback: $_flag_grid" >&2
        return 2
    end

    set -l rows $grid_parts[1]
    set -l cols $grid_parts[2]
    set -l cell_x $grid_parts[3]
    set -l cell_y $grid_parts[4]
    set -l cell_w $grid_parts[5]
    set -l cell_h $grid_parts[6]

    set -l display_json (ws_yabai -m query --displays --display $_flag_display 2>/dev/null)
    if test $status -ne 0 -o -z "$display_json"
        echo "[WARN] $caller could not query display $_flag_display for AppleScript bounds fallback" >&2
        return 1
    end

    set -l frame_values (echo $display_json | ws_jq -r '[.frame.x, .frame.y, .frame.w, .frame.h] | @tsv')
    if test -z "$frame_values"
        return 1
    end

    set -l frame_parts (string split \t -- "$frame_values")
    set -l frame_x $frame_parts[1]
    set -l frame_y $frame_parts[2]
    set -l frame_w $frame_parts[3]
    set -l frame_h $frame_parts[4]

    set -l left (math --scale=0 "round($frame_x + ($frame_w * $cell_x / $cols))")
    set -l top (math --scale=0 "round($frame_y + ($frame_h * $cell_y / $rows))")
    set -l width (math --scale=0 "round($frame_w * $cell_w / $cols)")
    set -l height (math --scale=0 "round($frame_h * $cell_h / $rows)")
    set -l right (math --scale=0 "$left + $width")
    set -l bottom (math --scale=0 "$top + $height")

    set -l app_names (workspace_app_names $_flag_app_key)
    or return 1

    set -l osascript_timeout "$WORKSPACE_OSASCRIPT_TIMEOUT_SECONDS"
    if test -z "$osascript_timeout"
        set osascript_timeout 3
    end

    for app_name in $app_names
        if set -q _flag_all_windows
            perl -e '
                my $timeout = shift;
                my $pid = fork();
                die "fork failed\n" unless defined $pid;
                if ($pid == 0) {
                    exec @ARGV;
                    exit 127;
                }
                local $SIG{ALRM} = sub {
                    kill "TERM", $pid;
                    sleep 1;
                    kill "KILL", $pid;
                    exit 124;
                };
                alarm $timeout;
                waitpid $pid, 0;
                exit(($? >> 8) || ($? & 127));
            ' $osascript_timeout osascript \
                -e "tell application \"$app_name\"" \
                -e "set didApply to false" \
                -e "repeat with targetWindow in windows" \
                -e "try" \
                -e "set bounds of targetWindow to {$left, $top, $right, $bottom}" \
                -e "set didApply to true" \
                -e "end try" \
                -e "end repeat" \
                -e "if didApply is false then error \"no scriptable window\"" \
                -e "end tell" >/dev/null 2>&1

            if test $status -eq 0
                return 0
            end

            perl -e '
                my $timeout = shift;
                my $pid = fork();
                die "fork failed\n" unless defined $pid;
                if ($pid == 0) {
                    exec @ARGV;
                    exit 127;
                }
                local $SIG{ALRM} = sub {
                    kill "TERM", $pid;
                    sleep 1;
                    kill "KILL", $pid;
                    exit 124;
                };
                alarm $timeout;
                waitpid $pid, 0;
                exit(($? >> 8) || ($? & 127));
            ' $osascript_timeout osascript \
                -e "tell application \"System Events\"" \
                -e "if not (exists process \"$app_name\") then error \"process not found\"" \
                -e "tell process \"$app_name\"" \
                -e "set didApply to false" \
                -e "repeat with targetWindow in windows" \
                -e "try" \
                -e "set position of targetWindow to {$left, $top}" \
                -e "set size of targetWindow to {$width, $height}" \
                -e "set didApply to true" \
                -e "end try" \
                -e "end repeat" \
                -e "if didApply is false then error \"no accessibility window\"" \
                -e "end tell" \
                -e "end tell" >/dev/null 2>&1

            if test $status -eq 0
                return 0
            end

            continue
        end

        perl -e '
            my $timeout = shift;
            my $pid = fork();
            die "fork failed\n" unless defined $pid;
            if ($pid == 0) {
                exec @ARGV;
                exit 127;
            }
            local $SIG{ALRM} = sub {
                kill "TERM", $pid;
                sleep 1;
                kill "KILL", $pid;
                exit 124;
            };
            alarm $timeout;
            waitpid $pid, 0;
            exit(($? >> 8) || ($? & 127));
        ' $osascript_timeout osascript \
            -e "tell application \"$app_name\"" \
            -e "set targetWindow to missing value" \
            -e "set targetArea to -1" \
            -e "repeat with candidateWindow in windows" \
            -e "set candidateBounds to bounds of candidateWindow" \
            -e "set candidateWidth to (item 3 of candidateBounds) - (item 1 of candidateBounds)" \
            -e "set candidateHeight to (item 4 of candidateBounds) - (item 2 of candidateBounds)" \
            -e "set candidateArea to candidateWidth * candidateHeight" \
            -e "if candidateArea > targetArea then" \
            -e "set targetArea to candidateArea" \
            -e "set targetWindow to candidateWindow" \
            -e "end if" \
            -e "end repeat" \
            -e "if targetWindow is missing value or targetArea <= 0 then error \"no scriptable window\"" \
            -e "set bounds of targetWindow to {$left, $top, $right, $bottom}" \
            -e "end tell" >/dev/null 2>&1

        if test $status -eq 0
            return 0
        end

        perl -e '
            my $timeout = shift;
            my $pid = fork();
            die "fork failed\n" unless defined $pid;
            if ($pid == 0) {
                exec @ARGV;
                exit 127;
            }
            local $SIG{ALRM} = sub {
                kill "TERM", $pid;
                sleep 1;
                kill "KILL", $pid;
                exit 124;
            };
            alarm $timeout;
            waitpid $pid, 0;
            exit(($? >> 8) || ($? & 127));
        ' $osascript_timeout osascript \
            -e "tell application \"System Events\"" \
            -e "if not (exists process \"$app_name\") then error \"process not found\"" \
            -e "tell process \"$app_name\"" \
            -e "set targetWindow to missing value" \
            -e "set targetArea to -1" \
            -e "repeat with candidateWindow in windows" \
            -e "try" \
            -e "set candidateSize to size of candidateWindow" \
            -e "set candidateArea to (item 1 of candidateSize) * (item 2 of candidateSize)" \
            -e "if candidateArea > targetArea then" \
            -e "set targetArea to candidateArea" \
            -e "set targetWindow to candidateWindow" \
            -e "end if" \
            -e "end try" \
            -e "end repeat" \
            -e "if targetWindow is missing value or targetArea <= 0 then error \"no accessibility window\"" \
            -e "set position of targetWindow to {$left, $top}" \
            -e "set size of targetWindow to {$width, $height}" \
            -e "end tell" \
            -e "end tell" >/dev/null 2>&1

        if test $status -eq 0
            return 0
        end
    end

    echo "[WARN] $caller could not apply AppleScript bounds fallback for $_flag_app_key" >&2
    return 1
end

function workspace_capture_app_window --description "Move a movable app window to a target space and confirm it landed there"
    argparse 'app=' 'caller=' 'space=' visible -- $argv
    or return 1

    if not set -q _flag_app; or not set -q _flag_space
        echo "usage: workspace_capture_app_window --app <app-name> --space <space> [--caller <name>] [--visible]" >&2
        return 1
    end

    set -l caller workspace_capture_app_window
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l find_args --app "$_flag_app" --caller "$caller"
    if set -q _flag_visible
        set -a find_args --visible
    end

    set -l window_id (workspace_find_app_window $find_args)
    set -l find_status $status

    if test "$find_status" -eq 1
        return 1
    end

    if test -n "$window_id"
        ws_move_windows_to_space $_flag_space $window_id
    else if test "$find_status" -eq 2
        return 2
    end

    set -l target_window (workspace_find_app_window $find_args --space $_flag_space --no-refresh --target-only)
    if test -n "$target_window"
        echo $target_window
        return 0
    end

    set window_id (workspace_find_app_window $find_args --space $_flag_space)
    set find_status $status

    if test "$find_status" -eq 1
        return 1
    end

    if test -n "$window_id"
        ws_move_windows_to_space $_flag_space $window_id
        set target_window (workspace_find_app_window $find_args --space $_flag_space --no-refresh --target-only)

        if test -n "$target_window"
            echo $target_window
            return 0
        end
    end

    if test "$find_status" -eq 2
        return 2
    end

    return 0
end

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

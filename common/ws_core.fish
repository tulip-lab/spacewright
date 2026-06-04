function ws_yabai --description "Run a yabai command with a bounded timeout"
    set -l timeout_seconds "$WORKSPACE_YABAI_COMMAND_TIMEOUT_SECONDS"

    if test -z "$timeout_seconds"
        if test (count $argv) -ge 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query"
            set timeout_seconds "$WORKSPACE_YABAI_QUERY_TIMEOUT_SECONDS"

            if test -z "$timeout_seconds"
                set timeout_seconds 15
            end
        else
            set timeout_seconds "$WORKSPACE_YABAI_OPERATION_TIMEOUT_SECONDS"

            if test -z "$timeout_seconds"
                set timeout_seconds 3
            end
        end
    end

    set -l output_file (mktemp -t ws-yabai-output.XXXXXX)
    set -l error_file (mktemp -t ws-yabai-error.XXXXXX)

    if test "$WORKSPACE_DEBUG_YABAI" = "1"
        set -l started_at (perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000')
        perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai $argv >$output_file 2>$error_file
        set -l status_code $status
        set -l ended_at (perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000')
        set -l elapsed (math $ended_at - $started_at)

        if test "$status_code" -eq 0
            cat $output_file
        else
            cat $error_file >&2
        end

        rm -f $output_file $error_file

        if test "$elapsed" -ge 500 -o "$status_code" -ne 0
            echo "[ws_yabai] {$elapsed}ms status=$status_code args=$argv" | string replace "{$elapsed}" "$elapsed" >&2
        end

        return $status_code
    end

    perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai $argv >$output_file 2>$error_file
    set -l status_code $status

    if test "$status_code" -eq 0
        cat $output_file
    else
        cat $error_file >&2
    end

    rm -f $output_file $error_file
    return $status_code
end

function ws_jq --description "Run jq against JSON with a bounded timeout"
    set -l timeout_seconds "$WORKSPACE_JQ_TIMEOUT_SECONDS"

    if test -z "$timeout_seconds"
        set timeout_seconds 3
    end

    perl -e 'alarm shift; exec @ARGV' $timeout_seconds jq $argv
end

function ws_query_windows --description "Query yabai windows with timeout and fail-closed warning"
    set -l caller $argv[1]
    set -l phase $argv[2]

    if test -z "$caller"
        set caller workspace
    end

    if test -z "$phase"
        set phase windows
    end

    set -l windows_json (ws_yabai -m query --windows 2>/dev/null)
    if test $status -ne 0 -o -z "$windows_json"
        set windows_json (__ws_query_windows_by_space)

        if test $status -ne 0 -o -z "$windows_json"
            echo "[WARN] $caller could not query $phase windows from yabai" >&2
            return 1
        end
    end

    echo $windows_json | ws_jq -e 'type == "array"' >/dev/null 2>&1
    if test $status -ne 0
        echo "[WARN] $caller received invalid $phase windows JSON from yabai" >&2
        return 1
    end

    echo $windows_json
end

function ws_query_displays --description "Query yabai displays with one retry and JSON validation"
    set -l caller $argv[1]
    set -l phase $argv[2]

    if test -z "$caller"
        set caller workspace
    end

    if test -z "$phase"
        set phase displays
    end

    for attempt in 1 2
        set -l displays_json (ws_yabai -m query --displays 2>/dev/null)
        if test $status -eq 0 -a -n "$displays_json"
            echo $displays_json | ws_jq -e 'type == "array"' >/dev/null 2>&1
            if test $status -eq 0
                echo $displays_json
                return 0
            end
        end

        if test "$attempt" -eq 1
            sleep 0.25
        end
    end

    echo "[WARN] $caller could not query $phase displays from yabai" >&2
    return 1
end

function ws_query_spaces --description "Query yabai spaces with one retry and JSON validation"
    set -l caller $argv[1]
    set -l phase $argv[2]

    if test -z "$caller"
        set caller workspace
    end

    if test -z "$phase"
        set phase spaces
    end

    for attempt in 1 2
        set -l spaces_json (ws_yabai -m query --spaces 2>/dev/null)
        if test $status -eq 0 -a -n "$spaces_json"
            echo $spaces_json | ws_jq -e 'type == "array"' >/dev/null 2>&1
            if test $status -eq 0
                echo $spaces_json
                return 0
            end
        end

        if test "$attempt" -eq 1
            sleep 0.25
        end
    end

    echo "[WARN] $caller could not query $phase spaces from yabai" >&2
    return 1
end

function ws_query_current_display --description "Query current yabai display with one retry and JSON validation"
    set -l caller $argv[1]
    set -l phase $argv[2]

    if test -z "$caller"
        set caller workspace
    end

    if test -z "$phase"
        set phase current-display
    end

    for attempt in 1 2
        set -l display_json (ws_yabai -m query --displays --display 2>/dev/null)
        if test $status -eq 0 -a -n "$display_json"
            echo $display_json | ws_jq -e 'type == "object"' >/dev/null 2>&1
            if test $status -eq 0
                echo $display_json
                return 0
            end
        end

        if test "$attempt" -eq 1
            sleep 0.25
        end
    end

    echo "[WARN] $caller could not query $phase current display from yabai" >&2
    return 1
end

function ws_query_current_space --description "Query current yabai space with one retry and JSON validation"
    set -l caller $argv[1]
    set -l phase $argv[2]

    if test -z "$caller"
        set caller workspace
    end

    if test -z "$phase"
        set phase current-space
    end

    for attempt in 1 2
        set -l space_json (ws_yabai -m query --spaces --space 2>/dev/null)
        if test $status -eq 0 -a -n "$space_json"
            echo $space_json | ws_jq -e 'type == "object"' >/dev/null 2>&1
            if test $status -eq 0
                echo $space_json
                return 0
            end
        end

        if test "$attempt" -eq 1
            sleep 0.25
        end
    end

    echo "[WARN] $caller could not query $phase current space from yabai" >&2
    return 1
end

function __ws_query_windows_by_space --description "Fallback windows query that merges per-space yabai results"
    set -l spaces_json (ws_query_spaces __ws_query_windows_by_space windows-by-space)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    set -l spaces (echo $spaces_json | ws_jq -r '.[].index')
    if test $status -ne 0 -o (count $spaces) -eq 0
        return 1
    end

    set -l windows_file (mktemp -t ws-yabai-windows-by-space.XXXXXX)
    set -l found 0

    for space in $spaces
        set -l space_windows (ws_yabai -m query --windows --space $space 2>/dev/null)
        if test $status -eq 0 -a -n "$space_windows"
            echo $space_windows | ws_jq -e 'type == "array"' >/dev/null 2>&1
            if test $status -eq 0
                printf "%s\n" "$space_windows" >>$windows_file
                set found 1
            end
        end
    end

    if test "$found" -ne 1
        rm -f $windows_file
        return 1
    end

    set -l merged_windows (ws_jq -s 'add' <$windows_file 2>/dev/null)
    set -l merge_status $status
    rm -f $windows_file

    if test "$merge_status" -ne 0 -o -z "$merged_windows"
        return 1
    end

    echo $merged_windows
end

function ws_focus_display --description "Focus a display only when it is not already focused"
    if test (count $argv) -lt 1
        echo "usage: ws_focus_display <display_index>"
        return 1
    end

    set -l target_display $argv[1]
    set -l current_display_json (ws_query_current_display ws_focus_display focus)
    if test $status -ne 0 -o -z "$current_display_json"
        return 1
    end

    set -l current_display (echo $current_display_json | ws_jq -r '.index')

    if test -z "$current_display"
        return 1
    end

    if test "$current_display" = "$target_display"
        return 0
    end

    ws_yabai -m display --focus $target_display >/dev/null 2>&1
end

function ws_focus_space --description "Focus a space only when it is not already focused"
    if test (count $argv) -lt 1
        echo "usage: ws_focus_space <space_index>"
        return 1
    end

    set -l target_space $argv[1]
    set -l current_space_json (ws_query_current_space ws_focus_space focus)
    if test $status -ne 0 -o -z "$current_space_json"
        return 1
    end

    set -l current_space (echo $current_space_json | ws_jq -r '.index')

    if test -z "$current_space"
        return 1
    end

    if test "$current_space" = "$target_space"
        return 0
    end

    ws_yabai -m space --focus $target_space >/dev/null 2>&1
end

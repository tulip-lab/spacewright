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
        echo "[WARN] $caller could not query $phase windows from yabai" >&2
        return 1
    end

    echo $windows_json | ws_jq -e 'type == "array"' >/dev/null 2>&1
    if test $status -ne 0
        echo "[WARN] $caller received invalid $phase windows JSON from yabai" >&2
        return 1
    end

    echo $windows_json
end

function ws_focus_display --description "Focus a display only when it is not already focused"
    if test (count $argv) -lt 1
        echo "usage: ws_focus_display <display_index>"
        return 1
    end

    set -l target_display $argv[1]
    set -l current_display_json (ws_yabai -m query --displays --display 2>/dev/null)
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
    set -l current_space_json (ws_yabai -m query --spaces --space 2>/dev/null)
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

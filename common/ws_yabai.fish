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

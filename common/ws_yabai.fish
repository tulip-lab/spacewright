function ws_yabai --description "Run a yabai command with a bounded timeout"
    set -l timeout_seconds "$WORKSPACE_YABAI_COMMAND_TIMEOUT_SECONDS"

    if test -z "$timeout_seconds"
        set timeout_seconds 5
    end

    if test "$WORKSPACE_DEBUG_YABAI" = "1"
        set -l started_at (perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000')
        perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai $argv
        set -l status_code $status
        set -l ended_at (perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000')
        set -l elapsed (math $ended_at - $started_at)

        if test "$elapsed" -ge 500 -o "$status_code" -ne 0
            echo "[ws_yabai] {$elapsed}ms status=$status_code args=$argv" >&2
        end

        return $status_code
    end

    perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai $argv
end

function ws_window --description "Run a yabai window command only when the window still exists"
    if test (count $argv) -lt 2
        return 1
    end

    set -l window_id $argv[1]

    if test -z "$window_id" -o "$window_id" = "null"
        return 0
    end

    if not string match -qr '^[0-9]+$' -- "$window_id"
        return 0
    end

    set -e argv[1]
    set -l command_args (string join ' ' -- $argv)
    set -l timeout_seconds "$WORKSPACE_YABAI_TIMEOUT_SECONDS"

    if test -z "$timeout_seconds"
        set timeout_seconds 1
    end

    set -l bad_window_ttl "$WORKSPACE_BAD_WINDOW_TTL_SECONDS"

    if test -z "$bad_window_ttl"
        set bad_window_ttl 600
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l bad_window_file $bad_window_dir/$window_id

    if test -f "$bad_window_file"
        set -l now (date +%s)
        set -l bad_at (cat "$bad_window_file" 2>/dev/null)

        if string match -qr '^[0-9]+$' -- "$bad_at"
            set -l age (math $now - $bad_at)

            if test "$age" -lt "$bad_window_ttl"
                if test "$WORKSPACE_DEBUG_WINDOW" = "1"
                    printf "[ws_window] skip-bad-window window=%s args=%s age=%ss\n" "$window_id" "$command_args" "$age"
                end

                return 0
            end
        end
    end

    if test "$argv[1]" = "--space" -a -n "$argv[2]"
        set -l current_window (perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai -m query --windows --window $window_id 2>/dev/null)

        if test $status -ne 0 -o -z "$current_window"
            mkdir -p "$bad_window_dir"
            date +%s >$bad_window_file

            if test "$WORKSPACE_DEBUG_WINDOW" = "1"
                printf "[ws_window] query-timeout window=%s args=%s\n" "$window_id" "$command_args"
            end

            return 0
        end

        set -l current_space (echo $current_window | ws_jq -r '.space // empty')

        if test "$current_space" = "$argv[2]"
            return 0
        end
    end

    if test "$WORKSPACE_DEBUG_WINDOW" = "1"
        set -l started_at (perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000')
        perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai -m window $window_id $argv >/dev/null 2>&1
        set -l status_code $status
        set -l ended_at (perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000')
        set -l elapsed (math $ended_at - $started_at)

        if test "$status_code" -eq 142
            mkdir -p "$bad_window_dir"
            date +%s >$bad_window_file
        end

        if test "$elapsed" -ge 500
            printf "[ws_window] %sms window=%s args=%s status=%s\n" "$elapsed" "$window_id" "$command_args" "$status_code"
        end

        return 0
    end

    perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai -m window $window_id $argv >/dev/null 2>&1
    set -l status_code $status

    if test "$status_code" -eq 142
        mkdir -p "$bad_window_dir"
        date +%s >$bad_window_file
    end

    return 0
end

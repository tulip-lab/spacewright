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
                    echo "[ws_window] skip-bad-window window=$window_id args=$argv age={$age}s"
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
                echo "[ws_window] query-timeout window=$window_id args=$argv"
            end

            return 0
        end

        set -l current_space (echo $current_window | jq -r '.space // empty')

        if test "$current_space" = "$argv[2]"
            return 0
        end
    end

    if test "$argv[1]" = "--grid" -a -n "$argv[2]"
        set -l cache_dir /tmp/workspace-ws-window-grid
        set -l cache_file $cache_dir/$window_id
        set -l current_window (perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai -m query --windows --window $window_id 2>/dev/null)

        if test $status -ne 0 -o -z "$current_window"
            mkdir -p "$bad_window_dir"
            date +%s >$bad_window_file

            if test "$WORKSPACE_DEBUG_WINDOW" = "1"
                echo "[ws_window] query-timeout window=$window_id args=$argv"
            end

            return 0
        end

        set -l current_frame (echo $current_window | jq -r '[.frame.x, .frame.y, .frame.w, .frame.h] | @tsv' 2>/dev/null)

        if test -n "$current_frame" -a -f "$cache_file"
            set -l cached (cat "$cache_file")
            set -l current_key (printf "%s\t%s" "$argv[2]" "$current_frame")

            if test "$cached" = "$current_key"
                return 0
            end
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

        if test "$argv[1]" = "--grid" -a -n "$argv[2]" -a "$status_code" -eq 0
            set -l cache_dir /tmp/workspace-ws-window-grid
            mkdir -p "$cache_dir"
            set -l updated_window (perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai -m query --windows --window $window_id 2>/dev/null)
            set -l updated_frame

            if test $status -eq 0 -a -n "$updated_window"
                set updated_frame (echo $updated_window | jq -r '[.frame.x, .frame.y, .frame.w, .frame.h] | @tsv' 2>/dev/null)
            end

            if test -n "$updated_frame"
                printf "%s\t%s\n" "$argv[2]" "$updated_frame" >$cache_dir/$window_id
            end
        end

        if test "$elapsed" -ge 500
            echo "[ws_window] {$elapsed}ms window=$window_id args=$argv status=$status_code"
        end

        return 0
    end

    perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai -m window $window_id $argv >/dev/null 2>&1
    set -l status_code $status

    if test "$status_code" -eq 142
        mkdir -p "$bad_window_dir"
        date +%s >$bad_window_file
    end

    if test "$argv[1]" = "--grid" -a -n "$argv[2]" -a "$status_code" -eq 0
        set -l cache_dir /tmp/workspace-ws-window-grid
        mkdir -p "$cache_dir"
        set -l updated_window (perl -e 'alarm shift; exec @ARGV' $timeout_seconds yabai -m query --windows --window $window_id 2>/dev/null)
        set -l updated_frame

        if test $status -eq 0 -a -n "$updated_window"
            set updated_frame (echo $updated_window | jq -r '[.frame.x, .frame.y, .frame.w, .frame.h] | @tsv' 2>/dev/null)
        end

        if test -n "$updated_frame"
            printf "%s\t%s\n" "$argv[2]" "$updated_frame" >$cache_dir/$window_id
        end
    end

    return 0
end

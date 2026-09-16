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
            set -l command_args (string join ' ' -- $argv)
            printf "[ws_yabai] %sms status=%s args=%s\n" "$elapsed" "$status_code" "$command_args" >&2
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

function ws_restart_yabai --description "Restart the yabai service through the bounded yabai wrapper"
    set -l caller $argv[1]

    if test -z "$caller"
        set caller workspace
    end

    set -l status_code 1
    set -l legacy_service "gui/"(id -u)"/com.asmvik.yabai"
    if command -q launchctl; and launchctl print "$legacy_service" >/dev/null 2>&1
        launchctl kickstart -k "$legacy_service" >/dev/null 2>&1
        set status_code $status
    else
        if not command -q yabai
            echo "[WARN] $caller cannot restart yabai because neither its LaunchAgent nor command is available" >&2
            return 1
        end
        ws_yabai --restart-service >/dev/null 2>&1
        set status_code $status
    end

    if test "$status_code" -ne 0
        echo "[WARN] $caller could not restart yabai service" >&2
    end

    return $status_code
end

function ws_yabai_auto_restart_allowed --description "Return success when a caller may restart yabai for workspace recovery"
    set -l caller $argv[1]

    if test "$WORKSPACE_DISABLE_YABAI_AUTO_RESTART" = "1"
        return 1
    end

    switch "$caller"
        case "" \
            work_audit \
            work_bad_windows \
            work_check \
            work_clear_bad_windows \
            work_diagnostics \
            work_display_health \
            work_doctor \
            work_smoke \
            work_status \
            yabai_doctor \
            workspace_plan \
            workspace_snapshot \
            workspace_verify \
            workspace_mode_status_section \
            workspace_print_app_status \
            workspace_status_snapshot \
            __ws_query_windows_by_space \
            '*_status'
            return 1
    end

    return 0
end

function ws_recover_yabai_once --description "Restart yabai at most once within a short recovery cooldown"
    set -l caller $argv[1]
    set -l reason $argv[2..-1]

    if test -z "$caller"
        set caller workspace
    end

    if test -z "$reason"
        set reason "yabai recovery requested"
    else
        set reason (string join ' ' -- $reason)
    end

    ws_yabai_auto_restart_allowed "$caller"
    or return 1

    set -l cooldown_seconds "$WORKSPACE_YABAI_RESTART_COOLDOWN_SECONDS"
    if test -z "$cooldown_seconds"
        set cooldown_seconds 10
    end

    set -l now (date +%s)
    if set -q __WORKSPACE_YABAI_AUTO_RESTART_AT
        if string match -qr '^[0-9]+$' -- "$__WORKSPACE_YABAI_AUTO_RESTART_AT"
            set -l age (math $now - $__WORKSPACE_YABAI_AUTO_RESTART_AT)
            if test "$age" -lt "$cooldown_seconds"
                workspace_debug_step $caller yabai-restart-recent age=$age reason="$reason"
                return 0
            end
        end
    end

    echo "[INFO] $caller $reason; restarting yabai once" >&2
    ws_restart_yabai "$caller"
    or return 1

    set -g __WORKSPACE_YABAI_AUTO_RESTART_AT $now
    if not set -q __WORKSPACE_YABAI_RESTART_GENERATION
        set -g __WORKSPACE_YABAI_RESTART_GENERATION 0
    end
    set -g __WORKSPACE_YABAI_RESTART_GENERATION (math $__WORKSPACE_YABAI_RESTART_GENERATION + 1)

    set -l settle_seconds "$WORKSPACE_YABAI_RESTART_SETTLE_SECONDS"
    if test -z "$settle_seconds"
        set settle_seconds 1
    end

    sleep $settle_seconds
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

    set -l failure_reason

    for recovery_attempt in 1 2
        set -l windows_json (ws_yabai -m query --windows 2>/dev/null)
        if test $status -ne 0 -o -z "$windows_json"
            set windows_json (__ws_query_windows_by_space)

            if test $status -ne 0 -o -z "$windows_json"
                set failure_reason "could not query $phase windows from yabai"
            end
        end

        if test -n "$windows_json"
            echo $windows_json | ws_jq -e 'type == "array"' >/dev/null 2>&1
            if test $status -eq 0
                echo $windows_json
                return 0
            end

            set failure_reason "received invalid $phase windows JSON from yabai"
        end

        if test "$recovery_attempt" -eq 1
            ws_recover_yabai_once "$caller" "$failure_reason"
            and continue
        end

        break
    end

    if test -z "$failure_reason"
        set failure_reason "could not query $phase windows from yabai"
    end

    echo "[WARN] $caller $failure_reason" >&2
    return 1
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

    for recovery_attempt in 1 2
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

        if test "$recovery_attempt" -eq 1
            ws_recover_yabai_once "$caller" "could not query $phase displays from yabai"
            and continue
        end

        break
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

    for recovery_attempt in 1 2
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

        if test "$recovery_attempt" -eq 1
            ws_recover_yabai_once "$caller" "could not query $phase spaces from yabai"
            and continue
        end

        break
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

    for recovery_attempt in 1 2
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

        if test "$recovery_attempt" -eq 1
            ws_recover_yabai_once "$caller" "could not query $phase current display from yabai"
            and continue
        end

        break
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

    for recovery_attempt in 1 2
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

        if test "$recovery_attempt" -eq 1
            ws_recover_yabai_once "$caller" "could not query $phase current space from yabai"
            and continue
        end

        break
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

function __ws_focus_target --description "Focus a display or space and treat already-focused as success"
    set -l kind $argv[1]
    set -l target $argv[2]

    if test -z "$kind" -o -z "$target"
        return 1
    end

    set -l focus_output (ws_yabai -m $kind --focus $target 2>&1)
    set -l focus_status $status

    if test "$focus_status" -eq 0
        return 0
    end

    if string match -qi "*already focused*" -- "$focus_output"
        return 0
    end

    if test -n "$focus_output"
        printf "%s\n" "$focus_output" >&2
    end

    return $focus_status
end

function ws_focus_display --description "Focus a display"
    if test (count $argv) -lt 1
        echo "usage: ws_focus_display <display_index>"
        return 1
    end

    set -l target_display $argv[1]
    __ws_focus_target display $target_display
end

function ws_focus_space --description "Focus a space"
    if test (count $argv) -lt 1
        echo "usage: ws_focus_space <space_index>"
        return 1
    end

    set -l target_space $argv[1]
    __ws_focus_target space $target_space
end

# Status contract: 0 applied/already satisfied, 2 optional absent, 3 invalid
# object, 4 command failure, 124 timeout/cached timeout. Optional callers decide
# whether absence is allowed; a selected object failing is never optional.
function ws_window --description "Operate on an extant window and propagate failure"
    test (count $argv) -ge 2; or return 3
    set -l window_id $argv[1]
    if test -z "$window_id" -o "$window_id" = null
        echo '[INFO] ws_window status=optional_skip' >&2
        return 2
    end
    string match -qr '^[1-9][0-9]*$' -- "$window_id"; or return 3
    set -e argv[1]
    set -l timeout_seconds "$WORKSPACE_YABAI_TIMEOUT_SECONDS"
    test -n "$timeout_seconds"; or set timeout_seconds 1
    set -l ttl "$WORKSPACE_BAD_WINDOW_TTL_SECONDS"
    test -n "$ttl"; or set ttl 60
    set -l state_root "$SPACEWRIGHT_STATE_ROOT"
    test -n "$state_root"; or set state_root "$HOME/.local/state/spacewright"
    set -l cache_dir "$state_root/cache/bad-windows"
    set -l cache_file "$cache_dir/$window_id"
    set -l generation "$SPACEWRIGHT_RUNTIME_GENERATION"
    test -n "$generation"; or set generation uncompiled
    set -l now (date +%s)
    set -lx WORKSPACE_YABAI_COMMAND_TIMEOUT_SECONDS "$timeout_seconds"
    set -l current (ws_yabai -m query --windows --window "$window_id")
    set -l query_status $status
    if test "$query_status" -ne 0
        set -l result 3
        contains -- "$query_status" 142 124; and set result 124
        printf '[WARN] ws_window status=query_failed window=%s exit=%s\n' "$window_id" "$query_status" >&2
        return $result
    end
    printf '%s\n' "$current" | ws_jq -e --argjson id "$window_id" 'type == "object" and .id == $id' >/dev/null
    or return 3
    if set -q SPACEWRIGHT_EXECUTION_ENVELOPE
        printf '%s\n' "$current" | command node "$SPACEWRIGHT_PACKAGE_ROOT/configurator/execution-cli.mjs" window-check "$window_id"
        or begin
            printf '[WARN] ws_window status=identity_invalid window=%s\n' "$window_id" >&2
            return 3
        end
    end
    set -l identity (__ws_window_cache_identity "$current")
    if test -r "$cache_file"
        jq -e --argjson identity "$identity" --arg generation "$generation" --argjson now "$now" --argjson ttl "$ttl" \
            '.identity == $identity and .generation == $generation and ($now - .at) >= 0 and ($now - .at) < $ttl' "$cache_file" >/dev/null 2>&1
        and begin
            printf '[WARN] ws_window status=cached_timeout window=%s\n' "$window_id" >&2
            return 124
        end
        rm -f "$cache_file"
    end
    if test "$argv[1]" = --space
        if test (printf '%s\n' "$current" | jq -r '.space') = "$argv[2]"
            printf '[INFO] ws_window status=already_satisfied window=%s\n' "$window_id" >&2
            return 0
        end
    end
    ws_yabai -m window "$window_id" $argv >/dev/null
    set -l command_status $status
    if test "$command_status" -eq 0
        return 0
    end
    if contains -- "$command_status" 124 142
        mkdir -p -m 700 "$cache_dir"
        set -l temporary (mktemp "$cache_dir/.timeout.XXXXXX")
        jq -n --argjson identity "$identity" --arg generation "$generation" --argjson now "$now" \
            '{identity:$identity,generation:$generation,at:$now}' >"$temporary"
        and mv "$temporary" "$cache_file"
        printf '[WARN] ws_window status=timeout window=%s\n' "$window_id" >&2
        return 124
    end
    printf '[WARN] ws_window status=command_failed window=%s exit=%s\n' "$window_id" "$command_status" >&2
    return 4
end

function ws_window_cache_active --description "Check cached failure against live application/process identity and runtime generation"
    set -l current $argv[1]
    set -l id (printf '%s\n' "$current" | jq -r '.id // empty')
    string match -qr '^[1-9][0-9]*$' -- "$id"; or return 1
    set -l file "$SPACEWRIGHT_STATE_ROOT/cache/bad-windows/$id"
    test -r "$file"; or return 1
    set -l identity (__ws_window_cache_identity "$current")
    set -l generation "$SPACEWRIGHT_RUNTIME_GENERATION"
    test -n "$generation"; or set generation uncompiled
    set -l ttl "$WORKSPACE_BAD_WINDOW_TTL_SECONDS"
    test -n "$ttl"; or set ttl 60
    jq -e --argjson identity "$identity" --arg generation "$generation" --argjson now (date +%s) --argjson ttl "$ttl" \
        '.identity == $identity and .generation == $generation and ($now-.at) >= 0 and ($now-.at) < $ttl' "$file" >/dev/null 2>&1
end

function __ws_window_cache_identity --description "Return app, PID and process-lifetime cache identity"
    set -l current $argv[1]
    set -l pid (printf '%s\n' "$current" | jq -r '.pid // 0')
    set -l fingerprint ''
    if string match -qr '^[0-9]+$' -- "$pid"; and test "$pid" -gt 1
        set fingerprint (command ps -p "$pid" -o lstart= -o command= 2>/dev/null | string trim)
    end
    printf '%s\n' "$current" | jq -c --arg fingerprint "$fingerprint" '{id,app,pid,bundle:(.["bundle-id"] // ""),process:$fingerprint}'
end

function __yabai_doctor_ok
    printf "OK      %s\n" "$argv"
end

function __yabai_doctor_warn
    printf "WARN    %s\n" "$argv"
end

function __yabai_doctor_fail
    printf "FAIL    %s\n" "$argv"
end

function __yabai_doctor_binary_path
    command -s yabai
end

function __yabai_doctor_real_path
    set -l path $argv[1]
    perl -MCwd=realpath -e 'print realpath($ARGV[0]) // $ARGV[0]' "$path"
end

function __yabai_doctor_sha256
    shasum -a 256 "$argv[1]" | string split ' ' | head -n 1
end

function __yabai_doctor_version
    "$argv[1]" --version 2>/dev/null
end

function __yabai_doctor_macos_version
    sw_vers -productVersion 2>/dev/null
end

function __yabai_doctor_head_active
    string match -q '*/Cellar/yabai/HEAD-*/bin/yabai' -- "$argv[1]"
end

function __yabai_doctor_head_required
    set -l macos_version (__yabai_doctor_macos_version)
    set -l parts (string split . -- "$macos_version")
    set -l major $parts[1]
    set -l minor 0

    if test (count $parts) -ge 2
        set minor $parts[2]
    end

    string match -rq '^[0-9]+$' -- "$major"
    or return 1
    string match -rq '^[0-9]+$' -- "$minor"
    or return 1

    test "$major" -gt 26
    and return 0

    test "$major" -eq 26 -a "$minor" -ge 6
end

function __yabai_doctor_loaded_service
    set -l user_id (id -u)

    for label in com.asmvik.yabai com.koekeishiya.yabai homebrew.mxcl.yabai
        set -l service "gui/$user_id/$label"
        if launchctl print "$service" >/dev/null 2>&1
            echo "$service"
            return 0
        end
    end

    return 1
end

function __yabai_doctor_service_running
    launchctl print "$argv[1]" 2>/dev/null |
        string match -rq '^[[:space:]]*state = running$'
end

function __yabai_doctor_sudo_rule_matches
    set -l path $argv[1]
    set -l hash $argv[2]
    set -l escaped_path (string escape --style=regex -- "$path")
    set -l rule_pattern (string join '' -- \
        'sha256:' "$hash" \
        '[[:space:]]+' "$escaped_path" \
        '[[:space:]]+--load-sa')

    sudo -n -l 2>/dev/null |
        string match -rq -- "$rule_pattern"
end

function __yabai_doctor_queries
    set -l displays (ws_query_displays yabai_doctor read-only)
    or return 1

    set -l spaces (ws_query_spaces yabai_doctor read-only)
    or return 1

    set -l windows (ws_query_windows yabai_doctor read-only)
    or return 1

    echo "displays="(echo "$displays" | ws_jq -r length)
    echo "spaces="(echo "$spaces" | ws_jq -r length)
    echo "windows="(echo "$windows" | ws_jq -r length)
end

function __yabai_doctor_check
    set -l failed 0

    echo "===== YABAI DOCTOR ====="

    set -l path (__yabai_doctor_binary_path)
    if test -z "$path"
        __yabai_doctor_fail "yabai command not found"
        return 1
    end
    __yabai_doctor_ok "binary=$path"

    set -l real_path (__yabai_doctor_real_path "$path")
    set -l hash (__yabai_doctor_sha256 "$path")
    set -l yabai_version (__yabai_doctor_version "$path")
    set -l macos_version (__yabai_doctor_macos_version)
    __yabai_doctor_ok "real_path=$real_path"
    __yabai_doctor_ok "version=$yabai_version"
    __yabai_doctor_ok "sha256=$hash"
    __yabai_doctor_ok "macOS=$macos_version"

    if __yabai_doctor_head_active "$real_path"
        __yabai_doctor_ok "HEAD build active"
    else if __yabai_doctor_head_required
        __yabai_doctor_fail "macOS 26.6 or newer requires the yabai HEAD Space fix"
        set failed 1
    else
        __yabai_doctor_warn "stable yabai build active"
    end

    set -l service (__yabai_doctor_loaded_service)
    if test -n "$service"
        __yabai_doctor_ok "LaunchAgent loaded: $service"
        if __yabai_doctor_service_running "$service"
            __yabai_doctor_ok "LaunchAgent running"
        else
            __yabai_doctor_fail "LaunchAgent loaded but not running"
            set failed 1
        end
    else
        __yabai_doctor_fail "yabai LaunchAgent not loaded"
        set failed 1
    end

    set -l query_output (__yabai_doctor_queries)
    set -l query_status $status
    if test "$query_status" -eq 0
        for line in $query_output
            __yabai_doctor_ok "query $line"
        end
    else
        __yabai_doctor_fail "yabai read-only queries failed"
        set failed 1
    end

    if __yabai_doctor_sudo_rule_matches "$path" "$hash"
        __yabai_doctor_ok "sudoers hash matches"
    else
        __yabai_doctor_fail "sudoers hash does not match"
        set failed 1
    end

    test "$failed" -eq 0
end

function __yabai_doctor_accessibility_missing
    set -l error_log /tmp/yabai_(whoami).err.log
    test -r "$error_log"
    or return 1

    tail -n 20 "$error_log" |
        string match -rq 'could not access accessibility features'
end

function __yabai_doctor_open_accessibility
    open 'x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility'
    echo "ACTION  remove and re-add /opt/homebrew/bin/yabai in Accessibility, then rerun:"
    echo "        yabai_doctor --repair"
end

function __yabai_doctor_ensure_head
    set -l path (__yabai_doctor_binary_path)
    if test -n "$path"
        set -l real_path (__yabai_doctor_real_path "$path")
        if __yabai_doctor_head_active "$real_path"
            echo "OK      yabai HEAD already active"
            return 0
        end
    end

    command -q brew
    or begin
        echo "FAIL    Homebrew not found" >&2
        return 1
    end

    echo "REPAIR  install yabai HEAD"
    if brew list --versions yabai >/dev/null 2>&1
        brew unlink yabai
        or return 1
    end

    brew install --HEAD asmvik/formulae/yabai
    or return 1

    set path (__yabai_doctor_binary_path)
    test -n "$path"
    or return 1

    __yabai_doctor_head_active (__yabai_doctor_real_path "$path")
end

function __yabai_doctor_validate_sudoers
    /usr/sbin/visudo -cf "$argv[1]"
end

function __yabai_doctor_install_sudoers_file
    sudo /usr/bin/install -o root -g wheel -m 440 \
        "$argv[1]" /private/etc/sudoers.d/yabai
end

function __yabai_doctor_install_sudoers
    set -l path (__yabai_doctor_binary_path)
    set -l hash (__yabai_doctor_sha256 "$path")
    test -n "$path" -a -n "$hash"
    or return 1

    set -l sudoers_tmp (mktemp)
    or return 1
    set -l install_status 1

    printf '%s ALL=(root) NOPASSWD: sha256:%s %s --load-sa\n' \
        (whoami) "$hash" "$path" >"$sudoers_tmp"

    if __yabai_doctor_validate_sudoers "$sudoers_tmp"
        echo "REPAIR  install hash-bound yabai sudoers rule"
        __yabai_doctor_install_sudoers_file "$sudoers_tmp"
        set install_status $status
    end

    rm -f "$sudoers_tmp"
    test "$install_status" -eq 0
end

function __yabai_doctor_load_sa
    set -l path (__yabai_doctor_binary_path)
    test -n "$path"
    or return 1

    echo "REPAIR  load yabai scripting addition"
    sudo -n "$path" --load-sa
end

function __yabai_doctor_space_probe
    set -l before (ws_query_spaces yabai_doctor_space_before read-only)
    or return 1

    echo "REPAIR  verify Space creation"
    ws_yabai -m space --create
    or return 1

    for attempt in (seq 1 20)
        sleep 0.25

        set -l after (ws_query_spaces yabai_doctor_space_after read-only)
        or continue

        set -l new_uuids (jq -nr \
            --argjson before "$before" \
            --argjson after "$after" \
            '$after | map(.uuid) - ($before | map(.uuid)) | .[]')

        if test (count $new_uuids) -eq 1
            set -l new_uuid $new_uuids[1]
            set -l new_index (echo "$after" | ws_jq -r \
                --arg uuid "$new_uuid" \
                '.[] | select(.uuid == $uuid) | .index')
            string match -rq '^[0-9]+$' -- "$new_index"
            or return 1

            ws_yabai -m space --destroy "$new_index"
            or return 1

            sleep 0.5
            set -l final (ws_query_spaces yabai_doctor_space_final read-only)
            or return 1
            set -l still_present (echo "$final" | ws_jq -r \
                --arg uuid "$new_uuid" \
                'any(.[]; .uuid == $uuid)')

            test "$still_present" = false
            return $status
        end

        if test (count $new_uuids) -gt 1
            echo "FAIL    ambiguous new Space identity; no Space destroyed" >&2
            return 1
        end
    end

    echo "FAIL    Space creation was not observed; no Space destroyed" >&2
    return 1
end

function __yabai_doctor_repair
    __yabai_doctor_ensure_head
    or begin
        echo "FAIL    repair phase=HEAD"
        return 1
    end

    __yabai_doctor_install_sudoers
    or begin
        echo "FAIL    repair phase=sudoers"
        return 1
    end

    __yabai_doctor_load_sa
    or begin
        echo "FAIL    repair phase=scripting_addition"
        return 1
    end

    echo "REPAIR  restart yabai LaunchAgent"
    ws_restart_yabai yabai_doctor
    or begin
        echo "FAIL    repair phase=service_restart"
        return 1
    end
    sleep 1

    __yabai_doctor_queries >/dev/null
    or begin
        if __yabai_doctor_accessibility_missing
            __yabai_doctor_open_accessibility
            echo "FAIL    manual Accessibility action required"
        else
            echo "FAIL    repair phase=daemon_query"
        end
        return 1
    end

    __yabai_doctor_space_probe
    or begin
        echo "FAIL    repair phase=space_probe"
        return 1
    end

    work_doctor
    or begin
        echo "FAIL    repair phase=work_doctor"
        return 1
    end

    __yabai_doctor_check
    or begin
        echo "FAIL    repair phase=final_check"
        return 1
    end

    echo "OK      repaired and verified"
end

function yabai_doctor --description "Diagnose yabai and optionally repair its runtime setup"
    argparse h/help repair -- $argv
    or begin
        echo "usage: yabai_doctor [--repair]" >&2
        return 2
    end

    if set -q _flag_help
        echo "usage: yabai_doctor [--repair]"
        return 0
    end

    if test (count $argv) -ne 0
        echo "usage: yabai_doctor [--repair]" >&2
        return 2
    end

    if set -q _flag_repair
        __yabai_doctor_repair
        return $status
    end

    __yabai_doctor_check
end

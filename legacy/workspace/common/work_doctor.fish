function work_doctor --description "Run read-only workspace system checks"
    set -l failed 0
    set -l warned 0

    function __work_doctor_ok
        printf "OK      %s\n" "$argv"
    end

    function __work_doctor_warn
        printf "WARN    %s\n" "$argv"
        set warned 1
    end

    function __work_doctor_fail
        printf "FAIL    %s\n" "$argv"
        set failed 1
    end

    set -l workspace_root ~/.config/fish/functions/workspace
    set -l displayprofiles_root ~/.config/displayprofiles

    echo "===== WORK DOCTOR ====="
    echo

    echo "===== TOOL CHECKS ====="
    for tool in fish jq yabai displayplacer skhd
        if command -q $tool
            __work_doctor_ok "$tool found"
        else
            __work_doctor_fail "$tool missing"
        end
    end

    echo
    echo "===== PATH CHECKS ====="
    for path in $workspace_root $displayprofiles_root ~/.config/skhd ~/.config/yabai
        if test -e $path
            if test -L $path
                __work_doctor_ok "$path exists (symlink)"
            else
                __work_doctor_ok "$path exists"
            end
        else
            __work_doctor_warn "$path missing"
        end
    end

    echo
    echo "===== SYNTAX CHECKS ====="
    if test -d $workspace_root
        set -l syntax_failed 0
        for file in (find $workspace_root -name '*.fish' -type f | sort)
            fish -n $file
            or begin
                __work_doctor_fail "fish syntax failed: $file"
                set syntax_failed 1
            end
        end

        if test "$syntax_failed" -eq 0
            __work_doctor_ok "workspace fish syntax"
        end
    else
        __work_doctor_fail "workspace function root missing"
    end

    if test -d $displayprofiles_root
        set -l display_syntax_failed 0
        for file in (find $displayprofiles_root -name '*.fish' -type f | sort)
            fish -n $file
            or begin
                __work_doctor_fail "display profile syntax failed: $file"
                set display_syntax_failed 1
            end
        end

        if test "$display_syntax_failed" -eq 0
            __work_doctor_ok "display profile fish syntax"
        end
    else
        __work_doctor_warn "display profile root missing"
    end

    echo
    echo "===== RELOAD AND ENTRY CHECKS ====="
    work_reload >/dev/null 2>&1
    if test $status -eq 0
        __work_doctor_ok "work_reload"
    else
        __work_doctor_fail "work_reload failed"
    end

    set -l command_check_output (work_command_check 2>&1)
    if test $status -eq 0
        __work_doctor_ok "work_command_check"
    else
        __work_doctor_fail "work_command_check failed"
        printf "%s\n" "$command_check_output"
    end

    set -l smoke_output (work_smoke 2>&1)
    if test $status -eq 0
        __work_doctor_ok "work_smoke"
    else
        __work_doctor_fail "work_smoke failed"
        printf "%s\n" "$smoke_output"
    end

    echo
    echo "===== YABAI READ-ONLY QUERIES ====="
    set -l displays_json (ws_query_displays work_doctor read-only)
    if test $status -eq 0 -a -n "$displays_json"
        set -l display_count (echo $displays_json | ws_jq -r 'length')
        __work_doctor_ok "displays query count=$display_count"

        set -l primary_uuid (get_workspace_primary_display_uuid 2>/dev/null)
        if test -n "$primary_uuid"
            set -l primary_present (echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" 'any(.[]; .uuid==$uuid)')
            if test "$primary_present" = "true"
                __work_doctor_ok "workspace primary display present"
            else
                __work_doctor_fail "workspace primary display not connected: $primary_uuid"
            end
        else if test "$display_count" -eq 1
            __work_doctor_ok "workspace primary display implicit from single display"
        else
            __work_doctor_fail "workspace primary display UUID is not configured"
        end
    else
        __work_doctor_fail "could not query yabai displays"
    end

    set -l spaces_json (ws_query_spaces work_doctor read-only)
    if test $status -eq 0 -a -n "$spaces_json"
        set -l space_count (echo $spaces_json | ws_jq -r 'length')
        set -l duplicate_label_count (echo $spaces_json | ws_jq -r 'map(select(.label != "")) | group_by(.label) | map(select(length > 1)) | length')
        set -l empty_labeled_count (echo $spaces_json | ws_jq -r '[.[] | select(.label != "" and (.windows | length) == 0)] | length')
        set -l empty_unlabeled_count (echo $spaces_json | ws_jq -r '[.[] | select(.label == "" and (.windows | length) == 0)] | length')
        __work_doctor_ok "spaces query count=$space_count"

        if test "$duplicate_label_count" -gt 0
            __work_doctor_fail "duplicate workspace labels count=$duplicate_label_count"
        else
            __work_doctor_ok "duplicate workspace labels none"
        end

        if test "$empty_labeled_count" -gt 0
            __work_doctor_warn "empty labeled spaces count=$empty_labeled_count"
        else
            __work_doctor_ok "empty labeled spaces none"
        end

        if test "$empty_unlabeled_count" -gt 0
            __work_doctor_warn "empty unlabeled spaces count=$empty_unlabeled_count"
        else
            __work_doctor_ok "empty unlabeled spaces none"
        end
    else
        __work_doctor_fail "could not query yabai spaces"
    end

    set -l windows_json (ws_query_windows work_doctor read-only)
    if test $status -eq 0 -a -n "$windows_json"
        set -l window_count (echo $windows_json | ws_jq -r 'length')
        __work_doctor_ok "windows query count=$window_count"
    else
        __work_doctor_fail "could not query yabai windows"
    end

    echo
    echo "===== DISPLAY HEALTH ====="
    work_display_health
    if test $status -eq 0
        __work_doctor_ok "display role health report"
    else
        __work_doctor_fail "display role health report failed"
    end

    echo
    work_bad_windows --summary

    echo
    echo "===== SUMMARY ====="
    if test "$failed" -eq 0
        if test "$warned" -eq 0
            echo "result=ok"
        else
            echo "result=ok_with_warnings"
        end
    else
        echo "result=failed"
    end

    functions -e __work_doctor_ok __work_doctor_warn __work_doctor_fail

    test "$failed" -eq 0
end

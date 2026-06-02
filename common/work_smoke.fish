function work_smoke --description "Run read-only workspace smoke checks for helper wiring and dry-run paths"
    set -l failed 0

    echo "===== WORKSPACE SMOKE ====="

    work_reload >/dev/null
    or set failed 1

    work_command_check >/tmp/work-command-check.out
    if test $status -eq 0
        echo "OK      command check"
    else
        echo "FAIL    command check"
        cat /tmp/work-command-check.out
        set failed 1
    end

    set -l app_keys \
        code codex chatgpt zotero thunderbird word powerpoint outlook zoom teams dia finder preview notes \
        calendar reminders wechat keybase messages dingtalk whatsapp warp smartgit keepassx flclash thaw

    for key in $app_keys
        workspace_app_name $key >/dev/null
        or begin
            echo "FAIL    app key $key"
            set failed 1
        end

        workspace_app_regex $key >/dev/null
        or begin
            echo "FAIL    app regex $key"
            set failed 1
        end
    end

    if test "$failed" -eq 0
        echo "OK      app registry"
    end

    set -l dry_run_commands \
        "work_solo --dry-run" \
        "work_wide --dry-run" \
        "work_tall --dry-run" \
        "coding_solo --dry-run" \
        "coding_wide --dry-run" \
        "coding_tall --dry-run" \
        "coding_editor_solo --dry-run" \
        "coding_editor_wide --dry-run" \
        "coding_editor_tall --dry-run" \
        "coding_control --dry-run" \
        "research_solo --dry-run" \
        "research_wide --dry-run" \
        "research_tall --dry-run" \
        "office_wide --dry-run" \
        "office_tall --dry-run" \
        "office_writing_wide --dry-run" \
        "office_writing_tall --dry-run" \
        "office_slides_wide --dry-run" \
        "office_slides_tall --dry-run" \
        "gtd_solo_all --dry-run" \
        "gtd_wide --dry-run" \
        "gtd_tall --dry-run" \
        "gtd_support_solo --dry-run" \
        "gtd_meeting_wide --dry-run" \
        "gtd_meeting_solo --dry-run" \
        "gtd_meeting_tall --dry-run" \
        "gtd_review_solo --dry-run" \
        "gtd_review_wide --dry-run" \
        "gtd_review_tall --dry-run" \
        "gtd_support_wide --dry-run" \
        "gtd_support_tall --dry-run" \
        "gtd_mail_solo --dry-run" \
        "gtd_mail_wide --dry-run" \
        "gtd_mail_tall --dry-run" \
        "gtd_chat --dry-run" \
        "gtd_calendar --dry-run"

    for dry_run_command in $dry_run_commands
        fish -lc "work_reload >/dev/null; $dry_run_command >/dev/null"
        if test $status -eq 0
            printf "OK      dry-run %s\n" "$dry_run_command"
        else
            printf "FAIL    dry-run %s\n" "$dry_run_command"
            set failed 1
        end
    end

    set -l retired_commands \
        ws_move_app_to_space \
        coding_wide_all \
        coding_tall_all \
        gtd_wide_all \
        gtd_tall_all \
        resolve_target_display

    for retired_command in $retired_commands
        if functions -q $retired_command
            printf "FAIL    retired command still loaded: %s\n" "$retired_command"
            set failed 1
        end
    end

    if test "$failed" -eq 0
        echo "result=ok"
    else
        echo "result=fail"
    end

    return $failed
end

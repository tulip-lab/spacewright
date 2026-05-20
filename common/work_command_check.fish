function work_command_check --description "Check that documented workspace command entry points are loaded"
    set -l commands \
        work_reload \
        work_diagnostics \
        work_check \
        work_status \
        work_mode_status \
        work_bad_windows \
        work_clear_bad_windows \
        work_cleanup_empty_labeled_spaces \
        work_cleanup_empty_unlabeled_spaces \
        work_recover_light \
        ws_yabai \
        ws_jq \
        ws_query_windows \
        ws_find_window \
        ws_find_windows \
        workspace_select_app_window \
        workspace_refresh_app_window \
        workspace_debug_step \
        workspace_run_step \
        display_reload \
        display_apply_solo \
        display_apply_wide_left \
        display_apply_tall_left \
        work_solo \
        work_wide \
        work_tall \
        detect_and_set_internal_display_uuid \
        set_internal_display_uuid \
        get_internal_display_uuid \
        gtd_reload \
        coding_reload \
        office_reload \
        research_reload \
        gtd_status \
        coding_status \
        office_status \
        research_status \
        gtd_mode_status \
        coding_mode_status \
        office_mode_status \
        research_mode_status \
        coding_solo \
        coding_wide \
        coding_tall \
        coding_wide_all \
        coding_tall_all \
        coding_control \
        research_solo \
        research_wide \
        research_tall \
        gtd_support_solo \
        gtd_support_wide \
        gtd_support_tall \
        gtd_review_solo \
        gtd_review_wide \
        gtd_review_tall \
        gtd_mail_solo \
        gtd_mail_wide \
        gtd_mail_tall \
        gtd_meeting_solo \
        gtd_meeting_wide \
        gtd_meeting_tall \
        gtd_solo_all \
        gtd_wide_all \
        gtd_tall_all \
        gtd_find_outlook_window \
        gtd_reopen_outlook \
        gtd_chat \
        gtd_calendar \
        office_wide \
        office_tall \
        office_writing_wide \
        office_writing_tall \
        office_slides_wide \
        office_slides_tall

    set -l missing_count 0

    echo "===== WORKSPACE COMMAND CHECK ====="

    for command_name in $commands
        if functions -q $command_name
            printf "OK      %s\n" "$command_name"
        else
            printf "MISSING %s\n" "$command_name"
            set missing_count (math $missing_count + 1)
        end
    end

    echo
    printf "missing_count=%s\n" "$missing_count"

    test "$missing_count" -eq 0
end

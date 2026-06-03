function work_command_check --description "Check that documented workspace command entry points are loaded"
    set -l commands \
        work_reload \
        work_diagnostics \
        work_display_health \
        work_check \
        work_status \
        work_mode_status \
        work_bad_windows \
        work_clear_bad_windows \
        workspace_cleanup_mode_spaces \
        workspace_cleanup_known_labeled_spaces \
        cleanup_unlabeled_empty_spaces \
        work_recover_light \
        work_inventory \
        work_doctor \
        work_smoke \
        ws_yabai \
        ws_jq \
        ws_query_windows \
        workspace_app_name \
        workspace_app_names \
        workspace_app_names_json \
        workspace_app_regex \
        ws_find_window \
        ws_find_windows \
        workspace_select_app_window \
        workspace_refresh_app_window \
        workspace_find_app_window \
        workspace_find_app_key_window \
        workspace_app_key_window_info \
        workspace_app_key_windows \
        workspace_app_key_space_fallback_info \
        workspace_apply_app_key_grid_bounds \
        workspace_capture_app_window \
        workspace_space_non_owned_windows \
        workspace_evict_non_owned_windows_from_space \
        workspace_debug_step \
        workspace_run_step \
        workspace_run_cleanup_specs \
        workspace_run_mode_steps \
        workspace_create_unlabeled_space_on_display \
        workspace_focus_labeled_space \
        workspace_focus_space_fallback \
        workspace_prepare_labeled_space \
        workspace_apply_primary_helper_space \
        workspace_retarget_contaminated_space \
        workspace_print_app_status \
        workspace_simple_module_status \
        display_reload \
        display_apply_profile_mode \
        display_verify_mode \
        display_apply_solo \
        display_apply_wide_left \
        display_apply_tall_left \
        work_solo \
        work_wide \
        work_tall \
        detect_and_set_workspace_primary_display_uuid \
        set_workspace_primary_display_uuid \
        get_workspace_primary_display_uuid \
        workspace_resolve_display_role \
        resolve_workspace_primary_display \
        resolve_workspace_external_display \
        gtd_reload \
        coding_reload \
        office_reload \
        research_reload \
        gtd_status \
        coding_status \
        office_status \
        research_status \
        coding_solo \
        coding_wide \
        coding_tall \
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
        gtd_find_outlook_window \
        gtd_find_meeting_window \
        gtd_find_meeting_windows \
        gtd_find_zoom_window \
        gtd_find_zoom_windows \
        gtd_find_teams_window \
        gtd_find_teams_windows \
        gtd_reopen_outlook \
        gtd_apply_meeting_space \
        gtd_apply_support_space \
        gtd_apply_review_space \
        gtd_support_find_dia_windows \
        gtd_support_layout_dia_windows \
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

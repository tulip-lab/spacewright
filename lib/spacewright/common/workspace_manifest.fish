function workspace_top_level_entry_rows --description "Print declared top-level workspace entries"
    printf "%s\t%s\t%s\n" work_solo "Arrange and finalize solo primary-display workspaces" "coding_solo research_solo gtd_solo_all"
    printf "%s\t%s\t%s\n" work_wide "Arrange and finalize wide external-display workspaces" "research_wide office_wide gtd_ai_wide gtd_support_wide gtd_review_wide coding_editor_wide gtd_ai_expand_hermes_when_alone gtd_mail_wide gtd_meeting_wide gtd_chat gtd_calendar coding_control"
    printf "%s\t%s\t%s\n" work_tall "Arrange and finalize tall external-display workspaces" "research_tall office_tall gtd_ai_tall gtd_support_tall gtd_review_tall coding_editor_tall gtd_ai_expand_hermes_when_alone gtd_mail_tall gtd_meeting_tall gtd_chat gtd_calendar coding_control"
    printf "%s\t%s\t%s\n" work_status "Inspect current workspace/display/module state" "diagnostics plus module status snapshots"
    printf "%s\t%s\t%s\n" work_reload "Reload common, display, and module functions" "reload only"
    printf "%s\t%s\t%s\n" work_check "Run reload, diagnostics, and module mode status" "read-only status"
    printf "%s\t%s\t%s\n" yabai_doctor "Diagnose or explicitly repair yabai" "read-only unless --repair"
    printf "%s\t%s\t%s\n" work_doctor "Run read-only system and config checks" "read-only validation"
    printf "%s\t%s\t%s\n" work_smoke "Run helper wiring and dry-run regression checks" "read-only regression"
    printf "%s\t%s\t%s\n" work_audit "Audit mode symmetry, ownership, helpers, and labels" "read-only architecture check"
end

function workspace_top_level_commands --description "Print declared child commands for a top-level workspace entry"
    set -l entry_name $argv[1]

    if test -z "$entry_name"
        echo "usage: workspace_top_level_commands <entry>" >&2
        return 2
    end

    switch "$entry_name"
        case work_solo work_wide work_tall
        case '*'
            return 1
    end

    for row in (workspace_top_level_entry_rows)
        set -l parts (string split \t -- "$row")
        if test "$parts[1]" = "$entry_name"
            string split ' ' -- "$parts[3]"
            return 0
        end
    end

    return 1
end

function workspace_module_entry_rows --description "Print declared workspace module entries"
    printf "%s\t%s\t%s\n" coding "solo, wide, tall" "Code; optional ChatGPT on wide/tall; primary-display coding_control"
    printf "%s\t%s\t%s\n" research "solo, wide, tall" "Zotero; optional Claude helper"
    printf "%s\t%s\t%s\n" gtd "solo_all, wide, tall, ai" "Hermes, Dia, Finder, Preview, Notes, ChatGPT, Obsidian, Thunderbird, Outlook, Zoom, Teams; primary-display chat/calendar"
    printf "%s\t%s\t%s\n" office "wide, tall" "Word, PowerPoint, ChatGPT"
end

function workspace_command_map_rows --description "Print declared workspace command map rows"
    printf "%s\t%s\t%s\t%s\n" coding_editor_solo solo primary Code
    printf "%s\t%s\t%s\t%s\n" coding_editor_wide wide external "Code, ChatGPT"
    printf "%s\t%s\t%s\t%s\n" coding_editor_tall tall external "Code, ChatGPT"
    printf "%s\t%s\t%s\t%s\n" coding_control primary primary "Warp, SmartGit, KeePassXC, FlClash/Thaw, Portfolio Performance"
    printf "%s\t%s\t%s\t%s\n" research_solo solo primary "Zotero, Claude"
    printf "%s\t%s\t%s\t%s\n" research_wide wide external "Zotero, Claude"
    printf "%s\t%s\t%s\t%s\n" research_tall tall external "Zotero, Claude"
    printf "%s\t%s\t%s\t%s\n" "gtd_support_*" all "mode target" Dia
    printf "%s\t%s\t%s\t%s\n" gtd_review_solo solo primary "Preview, Notes, ChatGPT, Finder"
    printf "%s\t%s\t%s\t%s\n" gtd_review_wide wide external "Preview, Obsidian, Notes, ChatGPT, Finder"
    printf "%s\t%s\t%s\t%s\n" gtd_review_tall tall external "Preview, Obsidian, Notes, ChatGPT, Finder"
    printf "%s\t%s\t%s\t%s\n" "gtd_mail_*" all "mode target" "Thunderbird, Outlook"
    printf "%s\t%s\t%s\t%s\n" "gtd_meeting_*" all "mode target" "Zoom, Teams"
    printf "%s\t%s\t%s\t%s\n" gtd_ai auto "current mode target" "Hermes, ChatGPT, Obsidian, Notes"
    printf "%s\t%s\t%s\t%s\n" "gtd_ai_*" all "mode target" "Hermes, ChatGPT, Obsidian, Notes"
    printf "%s\t%s\t%s\t%s\n" gtd_chat primary primary "Messages/chat helper windows, FaceTime"
    printf "%s\t%s\t%s\t%s\n" gtd_calendar primary primary Calendar
    printf "%s\t%s\t%s\t%s\n" "office_writing_*" "wide/tall" external "Word, ChatGPT"
    printf "%s\t%s\t%s\t%s\n" "office_slides_*" "wide/tall" external "PowerPoint, ChatGPT"
end

function workspace_finalized_entry_rows --description "Print public mutating workspace entries and their finalization modes"
    printf "%s\t%s\n" \
        work_solo solo \
        coding_editor_solo solo \
        coding_solo solo \
        research_solo solo \
        gtd_support_solo solo \
        gtd_review_solo solo \
        gtd_mail_solo solo \
        gtd_meeting_solo solo \
        gtd_ai_solo solo \
        gtd_solo_all solo \
        work_wide wide \
        coding_editor_wide wide \
        coding_wide wide \
        research_wide wide \
        office_writing_wide wide \
        office_slides_wide wide \
        office_wide wide \
        gtd_support_wide wide \
        gtd_review_wide wide \
        gtd_mail_wide wide \
        gtd_meeting_wide wide \
        gtd_ai_wide wide \
        gtd_wide wide \
        work_tall tall \
        coding_editor_tall tall \
        coding_tall tall \
        research_tall tall \
        office_writing_tall tall \
        office_slides_tall tall \
        office_tall tall \
        gtd_support_tall tall \
        gtd_review_tall tall \
        gtd_mail_tall tall \
        gtd_meeting_tall tall \
        gtd_ai_tall tall \
        gtd_tall tall \
        coding_control auto \
        gtd_chat auto \
        gtd_calendar auto
end

function workspace_display_entry_rows --description "Print declared display entry rows"
    printf "%s\t%s\n" display_apply_solo "apply solo display profile, reload, verify solo health"
    printf "%s\t%s\n" display_apply_wide_left "resolve current wide external display, reload, verify wide health"
    printf "%s\t%s\n" display_apply_tall_left "resolve current tall external display, reload, verify tall health"
end

function workspace_common_helper_rows --description "Print declared common workspace helper rows"
    printf "%s\t%s\n" ws_yabai "bounded yabai command wrapper"
    printf "%s\t%s\n" ws_restart_yabai "bounded yabai service restart wrapper"
    printf "%s\t%s\n" ws_recover_yabai_once "cooldown-guarded yabai restart recovery"
    printf "%s\t%s\n" ws_jq "bounded jq parser wrapper"
    printf "%s\t%s\n" ws_query_displays "bounded display query wrapper with retry"
    printf "%s\t%s\n" ws_query_spaces "bounded space query wrapper with retry"
    printf "%s\t%s\n" ws_query_current_display "bounded current-display query wrapper with retry"
    printf "%s\t%s\n" ws_query_current_space "bounded current-space query wrapper with retry"
    printf "%s\t%s\n" ws_query_windows "bounded window query wrapper"
    printf "%s\t%s\n" workspace_snapshot "single read-only display, Space, and window snapshot"
    printf "%s\t%s\n" workspace_plan "read-only live-state plan for supported workspaces"
    printf "%s\t%s\n" workspace_verify "read-only ownership and layout verification for supported workspaces"
    printf "%s\t%s\n" "workspace_app_name(s)/regex" "central workspace app-name registry"
    printf "%s\t%s\n" workspace_verify_primary_fixed_separation "Read-only gtd_chat/coding_control label and ownership verifier"
    printf "%s\t%s\n" workspace_reconcile_primary_fixed_spaces "One bounded gtd_chat then coding_control reconciliation pass"
    printf "%s\t%s\n" "ws_find_window/ws_find_windows" "structured window selectors"
    printf "%s\t%s\n" workspace_find_app_window "movable app-window selector with optional refresh"
    printf "%s\t%s\n" workspace_find_app_key_window "movable app-window selector across registered app aliases"
    printf "%s\t%s\n" workspace_app_key_window_info "first app-key window metadata from existing window JSON"
    printf "%s\t%s\n" workspace_app_key_windows "matching app-key window ids from existing window JSON"
    printf "%s\t%s\n" workspace_app_key_space_fallback_info "current-space fallback metadata for non-movable app-key windows"
    printf "%s\t%s\n" workspace_apply_app_key_grid_bounds "AppleScript/System Events bounds fallback for non-yabai-resizable app windows"
    printf "%s\t%s\n" workspace_apply_app_key_absolute_bounds "AppleScript absolute bounds fallback for fixed-position app windows"
    printf "%s\t%s\n" workspace_capture_app_window "find, move, and confirm app window on target space"
    printf "%s\t%s\n" workspace_space_non_owned_windows "window ids outside a workspace ownership regex"
    printf "%s\t%s\n" workspace_evict_non_owned_windows_from_space "move movable non-owned fallback-space windows to a holding space"
    printf "%s\t%s\n" workspace_apply_primary_helper_space "required primary app plus optional helper workspace flow"
    printf "%s\t%s\n" workspace_run_configured "validated configured-workspace runner with required-window preflight"
    printf "%s\t%s\n" office_apply_document_space "Office ChatGPT plus multi-document workspace flow"
    printf "%s\t%s\n" workspace_run_mode_steps "mode aggregate runner with shared cleanup suppression"
    printf "%s\t%s\n" workspace_run_cleanup_specs "family:mode cleanup-spec dispatcher"
    printf "%s\t%s\n" workspace_run_finalized_entry "outermost-only solo/wide/tall post-command runner"
    printf "%s\t%s\n" workspace_finalized_entry_rows "public mutating entries and required finalization modes"
    printf "%s\t%s\n" workspace_finalize_mode "Sandbox, cleanup, verified ordering, and focus restoration"
    printf "%s\t%s\n" workspace_apply_sandbox "policy-driven unmanaged-window Sandbox collection"
    printf "%s\t%s\n" workspace_space_occupant_windows_json "shared sticky and nonoccupying-ghost occupancy filter"
    printf "%s\t%s\n" workspace_cleanup_empty_spaces "unlabeled/Sandbox empty-Space cleanup with Home, managed-label, and ghost protection"
    printf "%s\t%s\n" workspace_order_mode_spaces "label-based solo, primary, and external Space ordering"
    printf "%s\t%s\n" workspace_order_and_verify_mode_spaces "Space ordering with one verification retry"
    printf "%s\t%s\n" workspace_verify_mode_space_order "read-only managed Space order verification"
    printf "%s\t%s\n" workspace_owned_app_keys "machine-readable ownership-policy app keys"
    printf "%s\t%s\n" workspace_owned_app_names_json "policy-owned yabai app names"
    printf "%s\t%s\n" workspace_home_space_info "leftmost unlabeled primary Home identity"
    printf "%s\t%s\n" workspace_sandbox_candidate_window_ids "unmanaged movable-window selector"
    printf "%s\t%s\n" workspace_detect_display_mode "solo/wide/tall display-mode detector"
    printf "%s\t%s\n" workspace_primary_order_labels "declared primary Space order"
    printf "%s\t%s\n" workspace_solo_order_labels "declared solo primary-display Space order"
    printf "%s\t%s\n" workspace_external_order_labels "declared mode-specific external Space order"
    printf "%s\t%s\n" workspace_print_app_status "shared app status printer for module status commands"
    printf "%s\t%s\n" workspace_prepare_labeled_space "find/create, normalize, and focus a labeled space"
    printf "%s\t%s\n" workspace_focus_labeled_space "normalize and focus an existing labeled space"
    printf "%s\t%s\n" workspace_focus_space_fallback "move and focus an app-owned fallback space by UUID"
    printf "%s\t%s\n" workspace_create_unlabeled_space_on_display "create an unlabeled holding space on a target display"
    printf "%s\t%s\n" find_or_create_labeled_space "label-based space creation and reuse"
    printf "%s\t%s\n" prepare_labeled_space "unique label ownership and layout normalization"
    printf "%s\t%s\n" workspace_retarget_contaminated_space "move labels away from mixed-owner spaces"
    printf "%s\t%s\n" workspace_ownership_policy "static workspace app ownership policy inventory"
    printf "%s\t%s\n" work_audit "read-only architecture and workspace-label drift checks"
    printf "%s\t%s\n" cleanup_labeled_empty_spaces "module-scoped empty labeled-space cleanup"
    printf "%s\t%s\n" cleanup_unlabeled_empty_spaces "transient empty space cleanup"
    printf "%s\t%s\n" workspace_resolve_display_role "primary/wide/tall display-role resolver"
    printf "%s\t%s\n" resolve_workspace_primary_display "configured primary workspace display role"
    printf "%s\t%s\n" resolve_workspace_external_display "current non-primary or fallback target display role"
end

function workspace_dependency_rows --description "Print declared workspace dependency rows"
    printf "%s\t%s\n" fish "function runtime and syntax validation"
    printf "%s\t%s\n" yabai "display, space, and window query/move layer"
    printf "%s\t%s\n" jq "JSON parsing"
    printf "%s\t%s\n" displayplacer "display profile application"
    printf "%s\t%s\n" skhd "keyboard entry layer"
    printf "%s\t%s\n" "macOS Spaces" "space labels and window placement"
end

function workspace_dry_run_commands --description "Print workspace commands that should support --dry-run"
    printf "%s\n" \
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
        "gtd_ai --dry-run" \
        "gtd_ai_solo --dry-run" \
        "gtd_ai_wide --dry-run" \
        "gtd_ai_tall --dry-run" \
        "gtd_chat --dry-run" \
        "gtd_calendar --dry-run"
end

function workspace_required_command_names --description "Print documented workspace command entry points that must be loaded"
    printf "%s\n" \
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
        yabai_doctor \
        work_doctor \
        work_smoke \
        work_smoke_observability \
        work_smoke_finalization \
        work_audit \
        workspace_top_level_entry_rows \
        workspace_top_level_commands \
        workspace_module_entry_rows \
        workspace_command_map_rows \
        workspace_finalized_entry_rows \
        workspace_display_entry_rows \
        workspace_common_helper_rows \
        workspace_dependency_rows \
        workspace_dry_run_commands \
        workspace_required_command_names \
        workspace_config_check \
        workspace_config_get \
        workspace_config_plan \
        workspace_run_configured \
        spacewright_config_effective \
        ws_yabai \
        ws_restart_yabai \
        ws_yabai_auto_restart_allowed \
        ws_recover_yabai_once \
        ws_jq \
        ws_query_displays \
        ws_query_spaces \
        ws_query_current_display \
        ws_query_current_space \
        ws_query_windows \
        workspace_snapshot \
        workspace_observation_workspaces \
        workspace_observation_spec \
        workspace_plan \
        workspace_verify \
        workspace_restore_labels \
        workspace_app_name \
        workspace_app_names \
        workspace_app_names_json \
        workspace_app_regex \
        workspace_verify_primary_fixed_separation \
        workspace_reconcile_primary_fixed_spaces \
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
        workspace_apply_app_key_absolute_bounds \
        workspace_capture_app_window \
        workspace_space_non_owned_windows \
        workspace_evict_non_owned_windows_from_space \
        workspace_debug_step \
        workspace_run_step \
        workspace_run_cleanup_specs \
        workspace_run_mode_steps \
        workspace_run_finalized_entry \
        workspace_finalize_mode \
        workspace_apply_sandbox \
        workspace_space_occupant_windows_json \
        workspace_cleanup_empty_spaces \
        workspace_order_mode_spaces \
        workspace_order_and_verify_mode_spaces \
        workspace_verify_mode_space_order \
        workspace_primary_order_labels \
        workspace_solo_order_labels \
        workspace_external_order_labels \
        workspace_home_space_info \
        workspace_sandbox_candidate_window_ids \
        workspace_owned_app_keys \
        workspace_owned_app_names_json \
        workspace_create_unlabeled_space_on_display \
        workspace_focus_labeled_space \
        workspace_focus_space_fallback \
        workspace_prepare_labeled_space \
        workspace_apply_primary_helper_space \
        workspace_retarget_contaminated_space \
        workspace_ownership_policy_rows \
        workspace_print_ownership_policy \
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
        workspace_detect_display_mode \
        resolve_workspace_primary_display \
        resolve_workspace_external_display \
        gtd_reload \
        coding_reload \
        office_reload \
        research_reload \
        gtd_status \
        coding_status \
        office_status \
        office_apply_document_space \
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
        gtd_ai \
        gtd_ai_solo \
        gtd_ai_wide \
        gtd_ai_tall \
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
        gtd_apply_ai_space \
        gtd_ai_detect_display_mode \
        gtd_ai_expand_hermes_when_alone \
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
end

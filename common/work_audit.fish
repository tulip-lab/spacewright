function __work_audit_dry_run_field --description "Print field values from a workspace command dry-run"
    set -l command_name $argv[1]
    set -l field_name $argv[2]

    if test -z "$command_name" -o -z "$field_name"
        echo "usage: __work_audit_dry_run_field <command> <field>" >&2
        return 2
    end

    set -l output ($command_name --dry-run 2>/dev/null)
    or return 1

    for line in $output
        if string match -q "$field_name=*" -- "$line"
            set -l field_value (string replace "$field_name=" "" -- "$line")
            if test -n "$field_value"
                string split ' ' -- "$field_value"
            end
        end
    end

    return 0
end

function __work_audit_check_exact_field --description "Check a dry-run field against an exact expected list"
    argparse 'command=' 'field=' 'label=' -- $argv
    or return 1

    if not set -q _flag_command; or not set -q _flag_field; or not set -q _flag_label
        echo "usage: __work_audit_check_exact_field --command <command> --field <field> --label <label> <expected...>" >&2
        return 2
    end

    set -l expected $argv
    set -l actual (__work_audit_dry_run_field $_flag_command $_flag_field)
    set -l actual_status $status

    if test "$actual_status" -ne 0
        printf "FAIL    %s: could not dry-run %s\n" "$_flag_label" "$_flag_command"
        return 1
    end

    set -l expected_join (string join ' ' -- $expected)
    set -l actual_join (string join ' ' -- $actual)

    if test "$expected_join" != "$actual_join"
        printf "FAIL    %s\n" "$_flag_label"
        printf "        expected %s %s: %s\n" "$_flag_command" "$_flag_field" "$expected_join"
        printf "        actual   %s %s: %s\n" "$_flag_command" "$_flag_field" "$actual_join"
        return 1
    end

    return 0
end

function __work_audit_check_mapped_field --description "Check that two dry-run fields match after token replacement"
    argparse 'left=' 'right=' 'field=' 'from=' 'to=' 'label=' -- $argv
    or return 1

    if not set -q _flag_left; or not set -q _flag_right; or not set -q _flag_field; or not set -q _flag_from; or not set -q _flag_to; or not set -q _flag_label
        echo "usage: __work_audit_check_mapped_field --left <command> --right <command> --field <field> --from <text> --to <text> --label <label>" >&2
        return 2
    end

    set -l left_values (__work_audit_dry_run_field $_flag_left $_flag_field)
    set -l left_status $status
    set -l right_values (__work_audit_dry_run_field $_flag_right $_flag_field)
    set -l right_status $status

    if test "$left_status" -ne 0
        printf "FAIL    %s: could not dry-run %s\n" "$_flag_label" "$_flag_left"
        return 1
    end

    if test "$right_status" -ne 0
        printf "FAIL    %s: could not dry-run %s\n" "$_flag_label" "$_flag_right"
        return 1
    end

    set -l expected
    for value in $left_values
        set -a expected (string replace -a "$_flag_from" "$_flag_to" -- "$value")
    end

    set -l expected_join (string join ' ' -- $expected)
    set -l actual_join (string join ' ' -- $right_values)

    if test "$expected_join" != "$actual_join"
        printf "FAIL    %s\n" "$_flag_label"
        printf "        expected %s %s: %s\n" "$_flag_right" "$_flag_field" "$expected_join"
        printf "        actual   %s %s: %s\n" "$_flag_right" "$_flag_field" "$actual_join"
        return 1
    end

    return 0
end

function __work_audit_check_policy_specs --description "Check required workspace ownership policy specs"
    set -l rows (workspace_ownership_policy_rows)
    set -l failed 0

    for spec in $argv
        set -l parts (string split '|' -- "$spec")
        set -l workspace_pattern $parts[1]
        set -l app_pattern $parts[2]
        set -l policy_pattern $parts[3]
        set -l match_pattern "*$workspace_pattern*$app_pattern*$policy_pattern*"

        string match -q $match_pattern -- $rows
        or begin
            printf "FAIL    ownership policy missing: workspace=%s app=%s policy=%s\n" "$workspace_pattern" "$app_pattern" "$policy_pattern"
            set failed 1
        end
    end

    return $failed
end

function __work_audit_check_loaded_functions --description "Check required workspace functions are loaded"
    set -l failed 0

    for command_name in $argv
        if not functions -q $command_name
            printf "FAIL    helper missing: %s\n" "$command_name"
            set failed 1
        end
    end

    return $failed
end

function __work_audit_mode_symmetry --description "Audit read-only solo/wide/tall wrapper symmetry"
    set -l failed 0

    echo "===== MODE SYMMETRY ====="

    __work_audit_check_exact_field \
        --command work_solo \
        --field commands \
        --label "mode symmetry: solo aggregate commands" \
        (workspace_top_level_commands work_solo)
    or set failed 1

    set -l command_pairs \
        "work_wide|work_tall" \
        "coding_wide|coding_tall" \
        "research_wide|research_tall" \
        "office_wide|office_tall" \
        "gtd_wide|gtd_tall"

    for pair in $command_pairs
        set -l parts (string split '|' -- "$pair")
        __work_audit_check_mapped_field \
            --left $parts[1] \
            --right $parts[2] \
            --field commands \
            --from _wide \
            --to _tall \
            --label "mode symmetry: $parts[1] commands map to $parts[2]"
        or set failed 1
    end

    set -l cleanup_pairs \
        "coding_wide|coding_tall" \
        "research_wide|research_tall" \
        "office_wide|office_tall" \
        "gtd_wide|gtd_tall"

    for pair in $cleanup_pairs
        set -l parts (string split '|' -- "$pair")
        __work_audit_check_mapped_field \
            --left $parts[1] \
            --right $parts[2] \
            --field cleanup \
            --from :tall \
            --to :wide \
            --label "mode symmetry: $parts[1] cleanup maps to $parts[2]"
        or set failed 1
    end

    if test "$failed" -eq 0
        echo "OK      mode symmetry: solo/wide/tall aggregate commands"
    end

    return $failed
end

function __work_audit_ownership_policy_coverage --description "Audit static ownership policy coverage"
    set -l failed 0

    echo "===== OWNERSHIP POLICY COVERAGE ====="

    __work_audit_check_policy_specs \
        "coding_editor_*|Code|single-window" \
        "coding_editor_wide/tall|ChatGPT|optional-helper" \
        "coding_control|FlClash/Thaw|all-movable-windows" \
        "research_*|Zotero|single-window" \
        "research_*|Claude|optional-helper" \
        "office_writing_*|Microsoft Word|all-movable-windows" \
        "office_writing_*|ChatGPT|optional-helper" \
        "office_slides_*|Microsoft PowerPoint|all-movable-windows" \
        "office_slides_*|ChatGPT|optional-helper" \
        "gtd_support_*|Dia|all-movable-windows" \
        "gtd_review_*|Finder|all-movable-windows" \
        "gtd_review_*|Preview|all-movable-windows;fallback-space-owner" \
        "gtd_review_*|Notes|all-movable-windows;fallback-space-owner" \
        "gtd_review_wide/tall|Obsidian|single-window" \
        "gtd_mail_*|Thunderbird|single-window;fallback-space-owner" \
        "gtd_mail_*|Microsoft Outlook|optional-helper" \
        "gtd_meeting_*|Zoom|all-movable-windows;fallback-space-owner" \
        "gtd_meeting_*|Microsoft Teams/MSTeams|all-movable-windows;fallback-space-owner" \
        "gtd_ai|ChatGPT|single-window" \
        "gtd_ai|Obsidian|single-window" \
        "gtd_ai|Notes|single-window" \
        "gtd_chat|DingTalk|single-window;fallback-space-owner" \
        "gtd_chat|FaceTime|single-window" \
        "gtd_calendar|Calendar|single-window;fallback-space-owner"
    or set failed 1

    if test "$failed" -eq 0
        echo "OK      ownership policy coverage"
    end

    return $failed
end

function __work_audit_fallback_helper_coverage --description "Audit fallback policy and helper coverage"
    set -l failed 0

    echo "===== FALLBACK HELPER COVERAGE ====="

    __work_audit_check_loaded_functions \
        workspace_app_key_space_fallback_info \
        workspace_focus_space_fallback \
        workspace_space_non_owned_windows \
        workspace_evict_non_owned_windows_from_space \
        workspace_create_unlabeled_space_on_display \
        workspace_apply_app_key_grid_bounds \
        workspace_apply_app_key_absolute_bounds
    or set failed 1

    __work_audit_check_policy_specs \
        "coding_control|SmartGit|fallback-space-owner" \
        "gtd_review_*|Preview|fallback-space-owner" \
        "gtd_review_*|Notes|fallback-space-owner" \
        "gtd_mail_*|Thunderbird|fallback-space-owner" \
        "gtd_meeting_*|Zoom|fallback-space-owner" \
        "gtd_meeting_*|Microsoft Teams/MSTeams|fallback-space-owner" \
        "gtd_chat|DingTalk|fallback-space-owner" \
        "gtd_calendar|Calendar|fallback-space-owner"
    or set failed 1

    if test "$failed" -eq 0
        echo "OK      fallback helper coverage"
    end

    return $failed
end

function __work_audit_multi_window_helper_coverage --description "Audit multi-window policy and helper coverage"
    set -l failed 0

    echo "===== MULTI-WINDOW HELPER COVERAGE ====="

    __work_audit_check_loaded_functions \
        ws_find_windows \
        workspace_app_key_windows \
        office_apply_document_space \
        gtd_apply_ai_space \
        gtd_find_meeting_windows \
        gtd_find_zoom_windows \
        gtd_find_teams_windows \
        gtd_support_find_dia_windows \
        gtd_support_layout_dia_windows \
        gtd_apply_review_space
    or set failed 1

    __work_audit_check_policy_specs \
        "coding_control|FlClash/Thaw|all-movable-windows" \
        "office_writing_*|Microsoft Word|all-movable-windows" \
        "office_slides_*|Microsoft PowerPoint|all-movable-windows" \
        "gtd_support_*|Dia|all-movable-windows" \
        "gtd_review_*|Finder|all-movable-windows" \
        "gtd_review_*|Preview|all-movable-windows" \
        "gtd_review_*|Notes|all-movable-windows" \
        "gtd_meeting_*|Zoom|all-movable-windows" \
        "gtd_meeting_*|Microsoft Teams/MSTeams|all-movable-windows"
    or set failed 1

    if test "$failed" -eq 0
        echo "OK      multi-window helper coverage"
    end

    return $failed
end

function __work_audit_finalization_coverage --description "Audit finalization helpers and policy keys"
    set -l failed 0
    echo "===== FINALIZATION COVERAGE ====="

    set -l helpers \
        workspace_owned_app_keys workspace_owned_app_names_json \
        workspace_home_space_info workspace_sandbox_candidate_window_ids workspace_apply_sandbox \
        workspace_space_occupant_windows_json workspace_cleanup_empty_spaces \
        workspace_detect_display_mode workspace_finalize_mode \
        workspace_run_finalized_entry workspace_primary_order_labels workspace_solo_order_labels \
        workspace_external_order_labels \
        workspace_verify_mode_space_order workspace_order_and_verify_mode_spaces

    __work_audit_check_loaded_functions $helpers
    or set failed 1

    set -l required (workspace_required_command_names)
    for helper in $helpers
        if not contains -- $helper $required
            echo "FAIL    finalization helper missing from manifest: $helper"
            set failed 1
        end
    end

    workspace_owned_app_keys >/dev/null
    or begin
        echo "FAIL    ownership policy app keys"
        set failed 1
    end

    if test $failed -eq 0
        echo "OK      finalization helper and policy coverage"
    end
    return $failed
end

function __work_audit_empty_label_allowlist_rows --description "Print labels that can legitimately be empty"
    printf "%s\t%s\n" "coding_control" "fixed internal control workspace; retained for visibility after tools close"
    printf "%s\t%s\n" "gtd_chat" "fixed primary-display chat workspace; optional chat apps may all be closed"
    printf "%s\t%s\n" "gtd_calendar" "fixed primary-display calendar workspace; Calendar or Reminders may be closed"
end

function __work_audit_empty_labeled_spaces --description "Audit empty labeled-space allowlist and current suspicious labels"
    echo "===== EMPTY LABELED SPACES ====="

    set -l allowed_labels
    for row in (__work_audit_empty_label_allowlist_rows)
        set -l parts (string split \t -- "$row")
        set -a allowed_labels $parts[1]
    end

    echo "OK      empty labeled-space allowlist"
    __work_audit_empty_label_allowlist_rows | while read -l row
        set -l parts (string split \t -- "$row")
        printf "        allow_empty=%s reason=%s\n" $parts[1] $parts[2]
    end

    set -l spaces_json (ws_query_spaces work_audit empty-labeled-spaces)
    if test $status -ne 0 -o -z "$spaces_json"
        echo "WARN    live empty labeled-space check skipped: yabai spaces query failed"
        return 0
    end

    set -l windows_json (ws_query_windows work_audit empty-labeled-windows)
    if test $status -ne 0 -o -z "$windows_json"
        echo "WARN    live empty labeled-space check skipped: yabai windows query failed"
        return 0
    end
    set -l occupant_windows_json (echo $windows_json | workspace_space_occupant_windows_json)
    if test $status -ne 0 -o -z "$occupant_windows_json"
        echo "WARN    live empty labeled-space check skipped: occupant-window filtering failed"
        return 0
    end

    set -l empty_rows (echo $spaces_json | ws_jq -r --argjson windows "$occupant_windows_json" '
        .[] | . as $space
        | select(.label != "" and ([$windows[] | select(.space==$space.index)] | length) == 0)
        | "\(.index)\t\(.label)\t\(.display)"')
    if test $status -ne 0
        echo "WARN    live empty labeled-space check skipped: spaces JSON parse failed"
        return 0
    end

    if test (count $empty_rows) -eq 0
        echo "OK      live empty labeled spaces: none"
        return 0
    end

    set -l suspicious_count 0

    for row in $empty_rows
        set -l parts (string split \t -- "$row")
        set -l space_index $parts[1]
        set -l label $parts[2]
        set -l display $parts[3]

        if contains -- "$label" $allowed_labels
            printf "OK      empty label by design: %s space=%s display=%s\n" "$label" "$space_index" "$display"
        else
            printf "WARN    suspicious empty labeled space: %s space=%s display=%s action=rerun owner mode or cleanup known labeled spaces\n" "$label" "$space_index" "$display"
            set suspicious_count (math $suspicious_count + 1)
        end
    end

    if test "$suspicious_count" -eq 0
        echo "OK      live empty labeled spaces are allowlisted"
    end

    return 0
end

function work_audit --description "Run read-only workspace mode and policy audit"
    set -l failed 0

    echo "===== WORKSPACE AUDIT ====="
    echo "read_only=true"
    echo

    __work_audit_mode_symmetry
    or set failed 1

    echo
    __work_audit_ownership_policy_coverage
    or set failed 1

    echo
    __work_audit_fallback_helper_coverage
    or set failed 1

    echo
    __work_audit_multi_window_helper_coverage
    or set failed 1

    echo
    __work_audit_finalization_coverage
    or set failed 1

    echo
    __work_audit_empty_labeled_spaces

    return $failed
end

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

    set -l localized_preview_fixture '[
        {"id": 18, "app": "预览", "space": 6, "can-move": true, "is-minimized": false}
    ]'
    set -l localized_preview_windows (echo $localized_preview_fixture | workspace_app_key_windows --app-key preview --movable)
    if test $status -eq 0 -a (string join , $localized_preview_windows) = "18"
        echo "OK      localized Preview selector"
    else
        echo "FAIL    localized Preview selector"
        set failed 1
    end

    set -l windows_by_space_query_smoke '
        work_reload >/dev/null

        function ws_yabai
            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--windows"
                return 1
            end

            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--spaces"
                printf "%s\n" "[
                    {\"index\": 1},
                    {\"index\": 2}
                ]"
                return 0
            end

            if test (count $argv) -eq 5 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--windows" -a "$argv[4]" = "--space"
                switch "$argv[5]"
                    case 1
                        printf "%s\n" "[{\"id\": 11, \"app\": \"SmartGit\", \"space\": 1}]"
                    case 2
                        printf "%s\n" "[{\"id\": 22, \"app\": \"Warp\", \"space\": 2}]"
                end
                return 0
            end

            return 1
        end

        set -l window_ids (ws_query_windows work_smoke initial | ws_jq -r ".[].id")
        or exit 1

        test (string join , $window_ids) = "11,22"
        or exit 2
    '
    fish -lc "$windows_by_space_query_smoke" >/tmp/work-windows-by-space-query-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      windows query per-space fallback"
    else
        echo "FAIL    windows query per-space fallback"
        cat /tmp/work-windows-by-space-query-smoke.out
        set failed 1
    end

    set -l displays_query_retry_smoke '
        work_reload >/dev/null

        set -g __work_smoke_display_query_calls 0

        function ws_yabai
            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--displays"
                set -g __work_smoke_display_query_calls (math $__work_smoke_display_query_calls + 1)
                if test "$__work_smoke_display_query_calls" -eq 1
                    return 1
                end

                printf "%s\n" "[
                    {\"index\": 1, \"uuid\": \"primary\", \"frame\": {\"x\": 0, \"y\": 0, \"w\": 1800, \"h\": 1169}},
                    {\"index\": 2, \"uuid\": \"external\", \"frame\": {\"x\": -3062, \"y\": -594, \"w\": 3062, \"h\": 1282}}
                ]"
                return 0
            end

            return 1
        end

        function get_workspace_primary_display_uuid
            echo primary
        end

        test (resolve_workspace_external_display wide) = 2
        or exit 1

        test "$__work_smoke_display_query_calls" -eq 2
        or exit 2
    '
    fish -lc "$displays_query_retry_smoke" >/tmp/work-displays-query-retry-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      displays query retry"
    else
        echo "FAIL    displays query retry"
        cat /tmp/work-displays-query-retry-smoke.out
        set failed 1
    end

    set -l spaces_query_retry_smoke '
        work_reload >/dev/null

        set -g __work_smoke_spaces_query_calls 0

        function ws_yabai
            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--spaces"
                set -g __work_smoke_spaces_query_calls (math $__work_smoke_spaces_query_calls + 1)
                if test "$__work_smoke_spaces_query_calls" -eq 1
                    return 1
                end

                printf "%s\n" "[
                    {\"index\": 1, \"display\": 1, \"label\": \"coding_control\"},
                    {\"index\": 2, \"display\": 2, \"label\": \"gtd_review_wide\"}
                ]"
                return 0
            end

            return 1
        end

        set -l labels (ws_query_spaces work_smoke retry | ws_jq -r ".[].label")
        or exit 1

        test (string join , $labels) = "coding_control,gtd_review_wide"
        or exit 2

        test "$__work_smoke_spaces_query_calls" -eq 2
        or exit 3
    '
    fish -lc "$spaces_query_retry_smoke" >/tmp/work-spaces-query-retry-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      spaces query retry"
    else
        echo "FAIL    spaces query retry"
        cat /tmp/work-spaces-query-retry-smoke.out
        set failed 1
    end

    set -l current_query_retry_smoke '
        work_reload >/dev/null

        set -g __work_smoke_current_display_query_calls 0
        set -g __work_smoke_current_space_query_calls 0

        function ws_yabai
            if test (count $argv) -eq 4 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--displays" -a "$argv[4]" = "--display"
                set -g __work_smoke_current_display_query_calls (math $__work_smoke_current_display_query_calls + 1)
                if test "$__work_smoke_current_display_query_calls" -eq 1
                    return 1
                end

                printf "%s\n" "{\"index\": 1}"
                return 0
            end

            if test (count $argv) -eq 4 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--spaces" -a "$argv[4]" = "--space"
                set -g __work_smoke_current_space_query_calls (math $__work_smoke_current_space_query_calls + 1)
                if test "$__work_smoke_current_space_query_calls" -eq 1
                    return 1
                end

                printf "%s\n" "{\"index\": 7}"
                return 0
            end

            return 1
        end

        test (ws_query_current_display work_smoke retry | ws_jq -r ".index") = 1
        or exit 1

        test (ws_query_current_space work_smoke retry | ws_jq -r ".index") = 7
        or exit 2

        test "$__work_smoke_current_display_query_calls" -eq 2
        or exit 3

        test "$__work_smoke_current_space_query_calls" -eq 2
        or exit 4
    '
    fish -lc "$current_query_retry_smoke" >/tmp/work-current-query-retry-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      current display/space query retry"
    else
        echo "FAIL    current display/space query retry"
        cat /tmp/work-current-query-retry-smoke.out
        set failed 1
    end

    set -l holding_space_reuse_smoke '
        work_reload >/dev/null

        function ws_yabai
            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--spaces"
                printf "%s\n" "[
                    {\"index\": 1, \"display\": 1, \"label\": \"coding_control\", \"windows\": [11]},
                    {\"index\": 2, \"display\": 1, \"label\": \"\", \"windows\": [999]},
                    {\"index\": 3, \"display\": 2, \"label\": \"\", \"windows\": []}
                ]"
                return 0
            end

            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--windows"
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"SmartGit\", \"space\": 1, \"is-sticky\": false},
                    {\"id\": 999, \"app\": \"Overlay\", \"space\": 2, \"is-sticky\": true}
                ]"
                return 0
            end

            if test "$argv[1]" = "-m" -a "$argv[2]" = "space" -a "$argv[3]" = "--create"
                exit 8
            end

            return 1
        end

        test (workspace_create_unlabeled_space_on_display 1) = 2
        or exit 1
    '
    fish -lc "$holding_space_reuse_smoke" >/tmp/work-holding-space-reuse-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      holding space reuse"
    else
        echo "FAIL    holding space reuse"
        cat /tmp/work-holding-space-reuse-smoke.out
        set failed 1
    end

    set -l ownership_policy_rows (workspace_ownership_policy_rows)

    set -l required_ownership_patterns \
        "*gtd_support_*Dia*all-movable-windows*" \
        "*gtd_review_*Finder*all-movable-windows*" \
        "*gtd_review_*Preview*all-movable-windows;fallback-space-owner*" \
        "*gtd_review_*Notes*single-window;fallback-space-owner*" \
        "*gtd_meeting_*Zoom*all-movable-windows;fallback-space-owner*" \
        "*gtd_meeting_*Microsoft Teams/MSTeams*all-movable-windows*" \
        "*gtd_mail_*Thunderbird*single-window;fallback-space-owner*" \
        "*gtd_calendar*Calendar*single-window;fallback-space-owner*" \
        "*coding_editor_*Code*single-window*" \
        "*coding_editor_*Codex*optional-helper;fallback-space-owner*" \
        "*coding_control*SmartGit*single-window;fallback-space-owner*" \
        "*research_*ChatGPT*optional-helper*" \
        "*office_writing_*Microsoft Word*single-window*"

    set -l ownership_failed 0
    for ownership_pattern in $required_ownership_patterns
        string match -q $ownership_pattern -- $ownership_policy_rows
        or begin
            echo "FAIL    ownership policy pattern: $ownership_pattern"
            set ownership_failed 1
            set failed 1
        end
    end

    if test "$ownership_failed" -eq 0
        echo "OK      ownership policy registry"
    end

    work_audit >/tmp/work-audit.out 2>&1
    set -l audit_status $status
    set -l audit_output
    if test -e /tmp/work-audit.out
        set audit_output (string collect </tmp/work-audit.out)
    end

    if test "$audit_status" -eq 0
            and string match -q "*===== WORKSPACE AUDIT =====*" -- "$audit_output"
            and string match -q "*OK      mode symmetry: wide/tall aggregate commands*" -- "$audit_output"
            and string match -q "*OK      ownership policy coverage*" -- "$audit_output"
            and string match -q "*OK      fallback helper coverage*" -- "$audit_output"
            and string match -q "*OK      empty labeled-space allowlist*" -- "$audit_output"
        echo "OK      workspace audit"
    else
        echo "FAIL    workspace audit"
        if test -e /tmp/work-audit.out
            cat /tmp/work-audit.out
        end
        set failed 1
    end

    set -l fallback_windows_fixture '[
        {"id": 11, "app": "Notes", "space": 6, "can-move": false, "is-minimized": false},
        {"id": 12, "app": "Preview", "space": 6, "can-move": true, "is-minimized": false},
        {"id": 13, "app": "Microsoft Word", "space": 6, "can-move": true, "is-minimized": false},
        {"id": 14, "app": "Finder", "space": 7, "can-move": true, "is-minimized": false},
        {"id": 15, "app": "Microsoft PowerPoint", "space": 6, "can-move": false, "is-minimized": false}
    ]'
    set -l non_owned_movable (echo $fallback_windows_fixture | workspace_space_non_owned_windows \
        --space 6 \
        --allowed-app-regex (workspace_app_regex finder preview chatgpt notes) \
        --movable)
    if test $status -eq 0 -a (string join , $non_owned_movable) = "13"
        echo "OK      fallback ownership selector"
    else
        echo "FAIL    fallback ownership selector"
        set failed 1
    end

    set -l fallback_eviction_smoke '
        work_reload >/dev/null

        set -g __work_smoke_moved ""
        set -g __work_smoke_focused ""

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 11, \"app\": \"Notes\", \"space\": 6, \"can-move\": false, \"is-minimized\": false},
                {\"id\": 12, \"app\": \"Preview\", \"space\": 6, \"can-move\": true, \"is-minimized\": false},
                {\"id\": 13, \"app\": \"Microsoft Word\", \"space\": 6, \"can-move\": true, \"is-minimized\": false},
                {\"id\": 14, \"app\": \"Finder\", \"space\": 7, \"can-move\": true, \"is-minimized\": false}
            ]"
        end

        function workspace_create_unlabeled_space_on_display
            echo 21
        end

        function ws_move_windows_to_space
            set -g __work_smoke_moved (string join , $argv)
        end

        function ws_focus_space
            set -g __work_smoke_focused $argv[1]
        end

        function workspace_debug_step
        end

        workspace_evict_non_owned_windows_from_space \
            --caller work_smoke \
            --space 6 \
            --target-display 2 \
            --allowed-app-regex (workspace_app_regex finder preview chatgpt notes)
        or exit 1

        test "$__work_smoke_moved" = "21,13"
        or exit 2

        test "$__work_smoke_focused" = "6"
        or exit 3
    '
    fish -lc "$fallback_eviction_smoke" >/tmp/work-fallback-eviction-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      fallback ownership eviction"
    else
        echo "FAIL    fallback ownership eviction"
        cat /tmp/work-fallback-eviction-smoke.out
        set failed 1
    end

    set -l review_fallback_eviction_smoke '
        work_reload >/dev/null

        set -g __work_smoke_review_eviction_calls

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 11, \"app\": \"Notes\", \"space\": 6, \"display\": 2, \"can-move\": false, \"is-minimized\": false, \"title\": \"Notes\"},
                {\"id\": 12, \"app\": \"Preview\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                {\"id\": 13, \"app\": \"Microsoft Word\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"draft\"},
                {\"id\": 14, \"app\": \"Finder\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
            ]"
        end

        function workspace_find_app_key_window
            if contains -- "--app-key" $argv
                set -l key_index (math (contains --index -- "--app-key" $argv) + 1)
                if test "$argv[$key_index]" = notes
                    return 2
                end
            end
        end

        function workspace_resolve_display_role
            echo 2
        end

        function workspace_focus_space_fallback
            argparse "label=" "space=" "source-display=" "target-display=" "layout=" "phase=" -- $argv
            echo $_flag_space
        end

        function workspace_evict_non_owned_windows_from_space
            set -ga __work_smoke_review_eviction_calls (string join " " -- $argv)
        end

        function ws_move_windows_to_space
        end

        function workspace_capture_app_window
        end

        function workspace_find_app_window
        end

        function ws_focus_space
        end

        function workspace_apply_app_key_grid_bounds
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_review_space --label gtd_review_wide --display wide
        or exit 1

        test (count $__work_smoke_review_eviction_calls) -ge 1
        or exit 2

        string match -q "*--space 6*" -- "$__work_smoke_review_eviction_calls[1]"
        or exit 3

        string match -q "*--allowed-app-regex*" -- "$__work_smoke_review_eviction_calls[1]"
        or exit 4
    '
    fish -lc "$review_fallback_eviction_smoke" >/tmp/work-review-fallback-eviction-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      review fallback ownership eviction"
    else
        echo "FAIL    review fallback ownership eviction"
        cat /tmp/work-review-fallback-eviction-smoke.out
        set failed 1
    end

    set -l review_snapshot_reconcile_smoke '
        work_reload >/dev/null

        set -g __work_smoke_review_move_calls

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            set -l phase $argv[2]

            if test "$phase" = initial
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 12, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            else if test "$phase" = final_review_reconcile
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 12, \"app\": \"Preview\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            else
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 12, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            end
        end

        function workspace_resolve_display_role
            echo 2
        end

        function find_or_create_labeled_space
            echo 8
        end

        function workspace_retarget_contaminated_space
            echo 8
        end

        function workspace_focus_labeled_space
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_review_move_calls (string join , -- $argv)
        end

        function ws_window
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_review_space --label gtd_review_wide --display wide --finder-grid 1:1:0:0:1:1 --preview-grid 1:1:0:0:1:1 --notes-grid 1:1:0:0:1:1
        or exit 1

        test "$__work_smoke_review_move_calls[1]" = "8,14,12,11"
        or exit 2

        test "$__work_smoke_review_move_calls[2]" = "8,14,12"
        or exit 3
    '
    fish -lc "$review_snapshot_reconcile_smoke" >/tmp/work-review-snapshot-reconcile-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      review snapshot Finder/Preview reconcile"
    else
        echo "FAIL    review snapshot Finder/Preview reconcile"
        cat /tmp/work-review-snapshot-reconcile-smoke.out
        set failed 1
    end

    set -l review_preview_movable_precedence_smoke '
        work_reload >/dev/null

        set -g __work_smoke_review_move_calls
        set -g __work_smoke_preview_fallback_called 0

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            set -l phase $argv[2]

            if test "$phase" = initial
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 12, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 13, \"app\": \"Preview\", \"space\": 5, \"display\": 2, \"can-move\": false, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            else
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 12, \"app\": \"Preview\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 13, \"app\": \"Preview\", \"space\": 5, \"display\": 2, \"can-move\": false, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            end
        end

        function workspace_resolve_display_role
            echo 2
        end

        function find_or_create_labeled_space
            echo 8
        end

        function workspace_retarget_contaminated_space
            echo 8
        end

        function workspace_focus_labeled_space
        end

        function workspace_focus_space_fallback
            set -g __work_smoke_preview_fallback_called 1
            echo 5
        end

        function workspace_evict_non_owned_windows_from_space
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_review_move_calls (string join , -- $argv)
        end

        function ws_window
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_review_space --label gtd_review_wide --display wide --finder-grid 1:1:0:0:1:1 --preview-grid 1:1:0:0:1:1 --notes-grid 1:1:0:0:1:1
        or exit 1

        test "$__work_smoke_preview_fallback_called" = 0
        or exit 2

        test "$__work_smoke_review_move_calls[1]" = "8,14,12,11"
        or exit 3
    '
    fish -lc "$review_preview_movable_precedence_smoke" >/tmp/work-review-preview-movable-precedence-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      review movable Preview precedence"
    else
        echo "FAIL    review movable Preview precedence"
        cat /tmp/work-review-preview-movable-precedence-smoke.out
        set failed 1
    end

    set -l review_preview_move_fallback_smoke '
        work_reload >/dev/null

        set -g __work_smoke_review_move_calls
        set -g __work_smoke_preview_fallback_args ""
        set -g __work_smoke_preview_eviction_args ""
        mkdir -p /tmp/workspace-ws-window-bad
        printf "%s\n" (date +%s) >/tmp/workspace-ws-window-bad/12
        printf "%s\n" (date +%s) >/tmp/workspace-ws-window-bad/16
        printf "%s\n" (date +%s) >/tmp/workspace-ws-window-bad/17

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            set -l phase $argv[2]

            if test "$phase" = initial
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 12, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            else if test "$phase" = preview_move_fallback
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 16, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 17, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            else if test "$phase" = preview_move_fallback_before_move
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 16, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 17, \"app\": \"Preview\", \"space\": 9, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            else
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 16, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 17, \"app\": \"Preview\", \"space\": 9, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            end
        end

        function workspace_resolve_display_role
            echo 2
        end

        function find_or_create_labeled_space
            echo 8
        end

        function workspace_retarget_contaminated_space
            echo 8
        end

        function workspace_focus_labeled_space
        end

        function workspace_focus_space_fallback
            set -g __work_smoke_preview_fallback_args (string join " " -- $argv)
            echo 6
        end

        function workspace_evict_non_owned_windows_from_space
            set -g __work_smoke_preview_eviction_args (string join " " -- $argv)
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_review_move_calls (string join , -- $argv)
        end

        function ws_window
        end

        function ws_focus_space
        end

        function workspace_apply_app_key_grid_bounds
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_review_space --label gtd_review_wide --display wide --finder-grid 1:1:0:0:1:1 --preview-grid 1:1:0:0:1:1 --notes-grid 1:1:0:0:1:1
        or exit 1

        test "$__work_smoke_review_move_calls[1]" = "8,14,12,11"
        or exit 2

        contains -- "8,16,17" $__work_smoke_review_move_calls
        or exit 3

        contains -- "6,14,16,17,11" $__work_smoke_review_move_calls
        or exit 4

        string match -q "*--space 6*" -- "$__work_smoke_preview_fallback_args"
        or exit 5

        string match -q "*--space 6*" -- "$__work_smoke_preview_eviction_args"
        or exit 6

        not test -e /tmp/workspace-ws-window-bad/12
        or exit 7

        not test -e /tmp/workspace-ws-window-bad/16
        or exit 8

        not test -e /tmp/workspace-ws-window-bad/17
        or exit 9
    '
    fish -lc "$review_preview_move_fallback_smoke" >/tmp/work-review-preview-move-fallback-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      review Preview failed-move fallback"
    else
        echo "FAIL    review Preview failed-move fallback"
        cat /tmp/work-review-preview-move-fallback-smoke.out
        set failed 1
    end

    set -l dia_fullscreen_fixture '[
        {"id": 31, "app": "Dia", "space": 8, "can-move": true, "is-minimized": false, "is-native-fullscreen": true},
        {"id": 32, "app": "Dia", "space": 8, "can-move": true, "is-minimized": false, "is-native-fullscreen": false}
    ]'
    set -l dia_non_fullscreen (echo $dia_fullscreen_fixture | ws_find_windows Dia --movable --not-native-fullscreen)
    if test $status -eq 0 -a (string join , $dia_non_fullscreen) = "32"
        echo "OK      Dia native-fullscreen selector"
    else
        echo "FAIL    Dia native-fullscreen selector"
        set failed 1
    end

    set -l support_retarget_smoke '
        work_reload >/dev/null

        set -g __work_smoke_support_retargeted 0
        set -g __work_smoke_support_moved ""

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            set -l phase $argv[2]

            if test "$phase" = initial
                printf "%s\n" "[
                    {\"id\": 31, \"app\": \"Dia\", \"space\": 3, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"is-native-fullscreen\": false},
                    {\"id\": 96, \"app\": \"Finder\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"is-native-fullscreen\": false}
                ]"
            else
                printf "%s\n" "[
                    {\"id\": 31, \"app\": \"Dia\", \"space\": 21, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"is-native-fullscreen\": false}
                ]"
            end
        end

        function workspace_resolve_display_role
            echo 2
        end

        function find_or_create_labeled_space
            echo 8
        end

        function workspace_prepare_labeled_space
            echo 8
        end

        function workspace_retarget_contaminated_space
            set -g __work_smoke_support_retargeted 1
            echo 21
        end

        function workspace_focus_labeled_space
        end

        function ws_move_windows_to_space
            set -g __work_smoke_support_moved (string join , -- $argv)
        end

        function ws_window
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_support_space --label gtd_support_wide --display wide --dia-layout wide
        or exit 1

        test "$__work_smoke_support_retargeted" = 1
        or exit 2

        test "$__work_smoke_support_moved" = "21,31"
        or exit 3
    '
    fish -lc "$support_retarget_smoke" >/tmp/work-support-retarget-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      support contaminated-space retarget"
    else
        echo "FAIL    support contaminated-space retarget"
        cat /tmp/work-support-retarget-smoke.out
        set failed 1
    end

    set -l codex_helper_fallback_smoke '
        work_reload >/dev/null

        set -g __work_smoke_helper_fallback_args ""
        set -g __work_smoke_helper_eviction_args ""
        set -g __work_smoke_helper_moved ""
        set -g __work_smoke_helper_bounds ""
        set -g __work_smoke_helper_grid ""

        function workspace_run_cleanup_specs
        end

        function workspace_resolve_display_role
            echo 2
        end

        function workspace_find_app_key_window
            argparse "app-key=" "space=" "caller=" "attempts=" "wait=" no-refresh target-only visible quiet-unmovable -- $argv

            switch "$_flag_app_key"
                case code
                    echo 11
                    return 0
                case codex
                    return 2
            end
        end

        function workspace_app_key_space_fallback_info
            printf "%s\t%s\t%s\n" 12 5 1
        end

        function workspace_focus_space_fallback
            set -g __work_smoke_helper_fallback_args (string join " " -- $argv)
            echo 5
        end

        function workspace_evict_non_owned_windows_from_space
            set -g __work_smoke_helper_eviction_args (string join " " -- $argv)
        end

        function workspace_prepare_labeled_space
            exit 8
        end

        function ws_move_windows_to_space
            set -g __work_smoke_helper_moved (string join , -- $argv)
        end

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 11, \"app\": \"Code\", \"space\": 5, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Code\"},
                {\"id\": 12, \"app\": \"Codex\", \"space\": 5, \"display\": 2, \"can-move\": false, \"is-minimized\": false, \"title\": \"Codex\"}
            ]"
        end

        function workspace_apply_app_key_grid_bounds
            set -g __work_smoke_helper_bounds (string join " " -- $argv)
        end

        function ws_window
            set -g __work_smoke_helper_grid (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        workspace_apply_primary_helper_space \
            --label coding_editor_wide \
            --display wide \
            --primary-app-key code \
            --helper-app-key codex \
            --helper-space-fallback \
            --helper-grid 1:3:0:0:1:1 \
            --primary-grid 1:3:1:0:2:1 \
            --primary-alone-grid 1:1:0:0:1:1
        or exit 1

        string match -q "*--space 5*" -- "$__work_smoke_helper_fallback_args"
        or exit 2

        string match -q "*--target-display 2*" -- "$__work_smoke_helper_fallback_args"
        or exit 3

        test "$__work_smoke_helper_moved" = "5,11"
        or exit 4

        string match -q "*--space 5*" -- "$__work_smoke_helper_eviction_args"
        or exit 5

        string match -q "*--app-key codex*" -- "$__work_smoke_helper_bounds"
        or exit 6

        string match -q "*--grid 1:3:0:0:1:1*" -- "$__work_smoke_helper_bounds"
        or exit 7

        test "$__work_smoke_helper_grid" = "11 --grid 1:3:1:0:2:1"
        or exit 8
    '
    fish -lc "$codex_helper_fallback_smoke" >/tmp/work-codex-helper-fallback-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      Codex helper space fallback"
    else
        echo "FAIL    Codex helper space fallback"
        cat /tmp/work-codex-helper-fallback-smoke.out
        set failed 1
    end

    set -l coding_control_smartgit_fallback_smoke '
        work_reload >/dev/null

        set -g __work_smoke_control_fallback_args ""
        set -g __work_smoke_control_eviction_args ""
        set -g __work_smoke_control_moved ""
        set -g __work_smoke_control_bounds ""
        set -g __work_smoke_control_grid ""

        function ws_query_windows
            set -l phase $argv[2]

            if test "$phase" = final
                printf "%s\n" "[
                    {\"id\": 21, \"app\": \"Warp\", \"space\": 6, \"display\": 1, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Warp\"},
                    {\"id\": 22, \"app\": \"SmartGit\", \"space\": 6, \"display\": 1, \"can-move\": false, \"is-minimized\": false, \"is-visible\": true, \"title\": \"SmartGit\"}
                ]"
            else
                printf "%s\n" "[
                    {\"id\": 21, \"app\": \"Warp\", \"space\": 3, \"display\": 1, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Warp\"},
                    {\"id\": 22, \"app\": \"SmartGit\", \"space\": 6, \"display\": 1, \"can-move\": false, \"is-minimized\": false, \"is-visible\": true, \"title\": \"SmartGit\"}
                ]"
            end
        end

        function workspace_find_app_key_window
            argparse "app-key=" "space=" "caller=" no-refresh target-only visible quiet-unmovable -- $argv

            switch "$_flag_app_key"
                case warp
                    echo 21
                    return 0
                case smartgit
                    return 2
                case keepassx
                    return 0
            end
        end

        function resolve_workspace_primary_display
            echo 1
        end

        function workspace_focus_space_fallback
            set -g __work_smoke_control_fallback_args (string join " " -- $argv)
            echo 6
        end

        function workspace_evict_non_owned_windows_from_space
            set -g __work_smoke_control_eviction_args (string join " " -- $argv)
        end

        function find_or_create_labeled_space
            exit 8
        end

        function workspace_retarget_contaminated_space
            exit 9
        end

        function workspace_focus_labeled_space
            exit 10
        end

        function ws_move_windows_to_space
            set -g __work_smoke_control_moved (string join , -- $argv)
        end

        function ws_window
            set -g __work_smoke_control_grid (string join " " -- $argv)
        end

        function workspace_apply_app_key_absolute_bounds
            set -g __work_smoke_control_bounds (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        coding_control
        or exit 1

        string match -q "*--space 6*" -- "$__work_smoke_control_fallback_args"
        or exit 2

        string match -q "*--target-display 1*" -- "$__work_smoke_control_fallback_args"
        or exit 3

        string match -q "*--space 6*" -- "$__work_smoke_control_eviction_args"
        or exit 4

        test "$__work_smoke_control_moved" = "6,21"
        or exit 5

        string match -q "*--app-key smartgit*" -- "$__work_smoke_control_bounds"
        or exit 6

        string match -q "*--x 300*" -- "$__work_smoke_control_bounds"
        or exit 7

        test "$__work_smoke_control_grid" = "21 --grid 3:1:0:0:1:2"
        or exit 8
    '
    fish -lc "$coding_control_smartgit_fallback_smoke" >/tmp/work-coding-control-smartgit-fallback-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      coding control SmartGit fallback"
    else
        echo "FAIL    coding control SmartGit fallback"
        cat /tmp/work-coding-control-smartgit-fallback-smoke.out
        set failed 1
    end

    set -l meeting_zoom_settle_smoke '
        work_reload >/dev/null

        set -g __work_smoke_zoom_any_calls 0
        set -g __work_smoke_zoom_late_visible 0
        set -g __work_smoke_zoom_moves
        set -g __work_smoke_zoom_grids

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            set -l phase $argv[2]

            switch "$phase"
                case initial
                    printf "%s\n" "[
                        {\"id\": 31, \"app\": \"Microsoft Outlook\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Outlook\"},
                        {\"id\": 41, \"app\": \"zoom.us\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"}
                    ]"
                case zoom_any
                    set -g __work_smoke_zoom_any_calls (math $__work_smoke_zoom_any_calls + 1)
                    if test "$__work_smoke_zoom_any_calls" -ge 3
                        printf "%s\n" "[
                            {\"id\": 41, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"},
                            {\"id\": 42, \"app\": \"zoom.us\", \"space\": 9, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Meeting\"}
                        ]"
                    else
                        printf "%s\n" "[
                            {\"id\": 41, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"}
                        ]"
                    end
                case zoom_target
                    if test "$__work_smoke_zoom_late_visible" = 1
                        printf "%s\n" "[
                            {\"id\": 41, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"},
                            {\"id\": 42, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Meeting\"}
                        ]"
                    else
                        printf "%s\n" "[
                            {\"id\": 41, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"}
                        ]"
                    end
                case final_zoom_settle_reconcile
                    set -g __work_smoke_zoom_late_visible 1
                    printf "%s\n" "[
                        {\"id\": 31, \"app\": \"Microsoft Outlook\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Outlook\"},
                        {\"id\": 41, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"},
                        {\"id\": 42, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Meeting\"}
                    ]"
                case teams_any teams_target
                    printf "%s\n" "[]"
                case "*"
                    printf "%s\n" "[
                        {\"id\": 31, \"app\": \"Microsoft Outlook\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Outlook\"},
                        {\"id\": 41, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"}
                    ]"
            end
        end

        function workspace_resolve_display_role
            echo 2
        end

        function find_or_create_labeled_space
            echo 8
        end

        function workspace_retarget_contaminated_space
            echo 8
        end

        function workspace_focus_labeled_space
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_zoom_moves (string join , -- $argv)
        end

        function ws_window
            set -ga __work_smoke_zoom_grids (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_meeting_space \
            --label gtd_meeting_wide \
            --display wide \
            --zoom-grid 2:5:0:0:2:1 \
            --teams-grid 2:5:0:1:2:1 \
            --outlook-grid 2:5:2:0:3:2
        or exit 1

        contains -- "8,41,42" $__work_smoke_zoom_moves
        or exit 2

        contains -- "41 --grid 2:5:0:0:2:1" $__work_smoke_zoom_grids
        or exit 3

        contains -- "42 --grid 2:5:0:0:2:1" $__work_smoke_zoom_grids
        or exit 4
    '
    fish -lc "$meeting_zoom_settle_smoke" >/tmp/work-meeting-zoom-settle-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      meeting Zoom settle reconciliation"
    else
        echo "FAIL    meeting Zoom settle reconciliation"
        cat /tmp/work-meeting-zoom-settle-smoke.out
        set failed 1
    end

    set -l meeting_hidden_zoom_fallback_smoke '
        work_reload >/dev/null

        set -g __work_smoke_zoom_fallback_called 0
        set -g __work_smoke_meeting_moves
        set -g __work_smoke_zoom_bounds_calls

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            set -l phase $argv[2]

            switch "$phase"
                case initial
                    printf "%s\n" "[
                        {\"id\": 31, \"app\": \"Microsoft Outlook\", \"space\": 6, \"display\": 1, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Outlook\"},
                        {\"id\": 41, \"app\": \"zoom.us\", \"space\": 6, \"display\": 1, \"can-move\": false, \"is-minimized\": false, \"is-visible\": false, \"title\": \"Zoom Workplace\"},
                        {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Teams\"}
                    ]"
                case zoom_any zoom_after_refresh zoom_space_fallback
                    printf "%s\n" "[
                        {\"id\": 41, \"app\": \"zoom.us\", \"space\": 6, \"display\": 1, \"can-move\": false, \"is-minimized\": false, \"is-visible\": false, \"title\": \"Zoom Workplace\"}
                    ]"
                case zoom_space_fallback_after_bounds zoom_space_fallback_after_bounds_confirm
                    printf "%s\n" "[
                        {\"id\": 41, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": false, \"is-minimized\": false, \"is-visible\": false, \"title\": \"Zoom Workplace\"}
                    ]"
                case teams_any teams_target
                    printf "%s\n" "[
                        {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Teams\"}
                    ]"
                case "*"
                    printf "%s\n" "[
                        {\"id\": 31, \"app\": \"Microsoft Outlook\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Outlook\"},
                        {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Teams\"},
                        {\"id\": 41, \"app\": \"zoom.us\", \"space\": 6, \"display\": 1, \"can-move\": false, \"is-minimized\": false, \"is-visible\": false, \"title\": \"Zoom Workplace\"}
                    ]"
            end
        end

        function workspace_resolve_display_role
            echo 2
        end

        function find_or_create_labeled_space
            echo 8
        end

        function workspace_retarget_contaminated_space
            echo 8
        end

        function workspace_focus_labeled_space
        end

        function workspace_focus_space_fallback
            set -g __work_smoke_zoom_fallback_called 1
            echo 8
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_meeting_moves (string join , -- $argv)
        end

        function workspace_apply_app_key_grid_bounds
            set -ga __work_smoke_zoom_bounds_calls (string join " " -- $argv)
            return 0
        end

        function ws_window
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_meeting_space \
            --label gtd_meeting_wide \
            --display wide \
            --zoom-grid 2:5:0:0:2:1 \
            --teams-grid 2:5:0:1:2:1 \
            --outlook-grid 2:5:2:0:3:2
        or exit 1

        test "$__work_smoke_zoom_fallback_called" = 1
        or exit 2

        contains -- "8,31,51" $__work_smoke_meeting_moves
        or exit 3

        string match -q "*--app-key zoom*--system-events-first*" -- "$__work_smoke_zoom_bounds_calls"
        or exit 4

        exit 0
    '
    fish -lc "$meeting_hidden_zoom_fallback_smoke" >/tmp/work-meeting-hidden-zoom-fallback-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      meeting hidden Zoom bounds fallback"
    else
        echo "FAIL    meeting hidden Zoom bounds fallback"
        cat /tmp/work-meeting-hidden-zoom-fallback-smoke.out
        set failed 1
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

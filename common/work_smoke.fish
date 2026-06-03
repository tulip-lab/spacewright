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

        set -g __work_smoke_review_evicted 0
        set -g __work_smoke_review_eviction_args ""

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
            set -g __work_smoke_review_evicted 1
            set -g __work_smoke_review_eviction_args (string join " " -- $argv)
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

        test "$__work_smoke_review_evicted" = 1
        or exit 2

        string match -q "*--space 6*" -- "$__work_smoke_review_eviction_args"
        or exit 3

        string match -q "*--allowed-app-regex*" -- "$__work_smoke_review_eviction_args"
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

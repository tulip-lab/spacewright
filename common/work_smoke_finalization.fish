function __work_smoke_finalization_policy
    set -l expected code chatgpt warp smartgit keepassx flclash thaw portfolio_performance \
        zotero claude word powerpoint dia finder preview notes obsidian thunderbird outlook \
        zoom teams wechat keybase dingtalk messages whatsapp facetime calendar reminders

    set -l actual (workspace_owned_app_keys)
    or return 1

    test (string join ' ' -- $actual) = (string join ' ' -- $expected)
    or return 2

    set -l names_json (workspace_owned_app_names_json)
    or return 3

    echo $names_json | ws_jq -e '
        index("Preview") != null and index("预览") != null and
        index("Microsoft Teams") != null and index("MSTeams") != null
    ' >/dev/null
    or return 4

    functions --copy workspace_ownership_policy_rows __workspace_real_policy_rows
    function workspace_ownership_policy_rows
        printf "%s\t%s\t%s\t%s\t%s\n" bad Bad single-window test missing_key
    end

    workspace_owned_app_keys >/dev/null 2>&1
    set -l invalid_status $status
    functions -e workspace_ownership_policy_rows
    functions --copy __workspace_real_policy_rows workspace_ownership_policy_rows
    functions -e __workspace_real_policy_rows

    test $invalid_status -ne 0
end

function __work_smoke_finalization_selection
    set -l spaces '[
      {"index":1,"uuid":"HOME","display":1,"label":""},
      {"index":2,"uuid":"CONTROL","display":1,"label":"coding_control"},
      {"index":7,"uuid":"OTHER","display":2,"label":""}
    ]'
    set -l windows '[
      {"id":11,"app":"Safari","space":7,"can-move":true,"is-sticky":false,"is-native-fullscreen":false,"is-minimized":false},
      {"id":12,"app":"Code","space":7,"can-move":true,"is-sticky":false,"is-native-fullscreen":false,"is-minimized":false},
      {"id":13,"app":"Slack","space":1,"can-move":true,"is-sticky":false,"is-native-fullscreen":false,"is-minimized":false},
      {"id":14,"app":"Spotify","space":7,"can-move":true,"is-sticky":true,"is-native-fullscreen":false,"is-minimized":false},
      {"id":15,"app":"Firefox","space":7,"can-move":true,"is-sticky":false,"is-native-fullscreen":true,"is-minimized":false},
      {"id":16,"app":"Terminal","space":7,"can-move":false,"is-sticky":false,"is-native-fullscreen":false,"is-minimized":false},
      {"id":17,"app":"Discord","space":7,"can-move":true,"is-sticky":false,"is-native-fullscreen":false,"is-minimized":true}
    ]'

    set -l home_info (echo $spaces | workspace_home_space_info --display 1)
    or return 1
    test "$home_info" = "HOME	1"
    or return 2

    set -l ids (echo $windows | workspace_sandbox_candidate_window_ids --home-space 1)
    or return 3
    test (string join ' ' -- $ids) = '11 17'
end

function __work_smoke_finalization_sandbox
    set -g __work_smoke_sandbox_scenario normal
    set -g __work_smoke_sandbox_queries 0
    set -g __work_smoke_sandbox_create
    set -g __work_smoke_sandbox_prepare
    set -g __work_smoke_sandbox_moves
    set -g __work_smoke_sandbox_yabai

    function ws_query_windows
        set -g __work_smoke_sandbox_queries (math $__work_smoke_sandbox_queries + 1)
        switch "$__work_smoke_sandbox_scenario"
            case empty
                echo '[]'
            case missing
                if test $__work_smoke_sandbox_queries -eq 1
                    echo '[{"id":11,"app":"Safari","space":6,"can-move":true,"is-sticky":false,"is-native-fullscreen":false}]'
                else
                    echo '[{"id":11,"app":"Safari","space":6,"can-move":true,"is-sticky":false,"is-native-fullscreen":false}]'
                end
            case '*'
                if test $__work_smoke_sandbox_queries -eq 1
                    echo '[
                      {"id":11,"app":"Safari","space":6,"can-move":true,"is-sticky":false,"is-native-fullscreen":false},
                      {"id":17,"app":"Discord","space":7,"can-move":true,"is-sticky":false,"is-native-fullscreen":false}
                    ]'
                else
                    echo '[
                      {"id":11,"app":"Safari","space":8,"can-move":true,"is-sticky":false,"is-native-fullscreen":false},
                      {"id":17,"app":"Discord","space":8,"can-move":true,"is-sticky":false,"is-native-fullscreen":false}
                    ]'
                end
        end
    end

    function find_or_create_labeled_space
        set -g __work_smoke_sandbox_create (string join ' ' -- $argv)
        echo 8
    end

    function prepare_labeled_space
        set -g __work_smoke_sandbox_prepare (string join ' ' -- $argv)
    end

    function ws_move_windows_to_space
        set -g __work_smoke_sandbox_moves (string join ' ' -- $argv)
    end

    function ws_yabai
        set -ga __work_smoke_sandbox_yabai (string join ' ' -- $argv)
    end

    workspace_apply_sandbox --mode wide --home-space 1 --display 2
    or return 1
    test "$__work_smoke_sandbox_create" = 'sandbox_wide 2'; or return 2
    test "$__work_smoke_sandbox_prepare" = '8 sandbox_wide bsp'; or return 3
    test "$__work_smoke_sandbox_moves" = '8 11 17'; or return 4
    contains -- '-m space 8 --layout bsp' $__work_smoke_sandbox_yabai; or return 5
    contains -- '-m space 8 --balance' $__work_smoke_sandbox_yabai; or return 6

    set -g __work_smoke_sandbox_scenario empty
    set -g __work_smoke_sandbox_queries 0
    set -g __work_smoke_sandbox_create
    set -g __work_smoke_sandbox_prepare
    set -g __work_smoke_sandbox_moves
    set -g __work_smoke_sandbox_yabai
    workspace_apply_sandbox --mode wide --home-space 1 --display 2
    or return 7
    test -z "$__work_smoke_sandbox_create$__work_smoke_sandbox_prepare$__work_smoke_sandbox_moves$__work_smoke_sandbox_yabai"
    or return 8

    set -g __work_smoke_sandbox_scenario missing
    set -g __work_smoke_sandbox_queries 0
    workspace_apply_sandbox --mode wide --home-space 1 --display 2 >/dev/null 2>&1
    test $status -ne 0
end

function __work_smoke_finalization_cleanup
    set -g __work_smoke_cleanup_scenario normal
    set -g __work_smoke_cleanup_destroyed
    set -g __work_smoke_cleanup_focused

    function ws_query_spaces
        if test "$__work_smoke_cleanup_scenario" = failure
            return 1
        end
        echo '[
          {"index":1,"uuid":"HOME","display":1,"label":""},
          {"index":2,"uuid":"CONTROL","display":1,"label":"coding_control"},
          {"index":3,"uuid":"OLD","display":2,"label":"sandbox_tall"},
          {"index":4,"uuid":"FOCUSED","display":2,"label":""},
          {"index":5,"uuid":"STICKY","display":2,"label":""},
          {"index":6,"uuid":"KEPT","display":2,"label":"gtd_review_wide"},
          {"index":7,"uuid":"ONLY","display":3,"label":""}
        ]'
    end

    function ws_query_windows
        echo '[
          {"id":21,"space":2,"is-sticky":false},
          {"id":50,"space":5,"is-sticky":true},
          {"id":60,"space":6,"is-sticky":false}
        ]'
    end

    function ws_focus_space
        set -ga __work_smoke_cleanup_focused $argv[1]
    end

    function ws_yabai
        if contains -- --destroy $argv
            set -ga __work_smoke_cleanup_destroyed $argv[3]
        end
    end

    workspace_cleanup_empty_spaces --home-uuid HOME --focus-uuid FOCUSED
    or return 1
    test (string join ' ' -- $__work_smoke_cleanup_destroyed) = 'STICKY FOCUSED OLD'
    or return 2
    test (string join ' ' -- $__work_smoke_cleanup_focused) = '6'
    or return 3
    not contains -- HOME $__work_smoke_cleanup_destroyed; or return 4
    not contains -- ONLY $__work_smoke_cleanup_destroyed; or return 5

    set -g __work_smoke_cleanup_scenario failure
    set -g __work_smoke_cleanup_destroyed
    workspace_cleanup_empty_spaces --home-uuid HOME --focus-uuid FOCUSED >/dev/null 2>&1
    test $status -ne 0; or return 6
    test (count $__work_smoke_cleanup_destroyed) -eq 0
end

function __work_smoke_finalization_ordering
    set -l dry_run (workspace_order_mode_spaces --dry-run wide)
    string match -q '*external=gtd_ai,coding_editor_wide,research_wide,office_writing_wide,office_slides_wide,gtd_support_wide,gtd_review_wide,gtd_mail_wide,gtd_meeting_wide,sandbox_wide*' -- "$dry_run"
    or return 1

    set -g __work_smoke_order_scenario good
    function resolve_workspace_primary_display
        echo 1
    end
    function workspace_resolve_display_role
        echo 2
    end
    function ws_query_spaces
        switch "$__work_smoke_order_scenario"
            case interleaved
                echo '[
                  {"index":1,"uuid":"HOME","display":1,"label":""},
                  {"index":2,"uuid":"CONTROL","display":1,"label":"coding_control"},
                  {"index":3,"uuid":"CHAT","display":1,"label":"gtd_chat"},
                  {"index":4,"uuid":"CAL","display":1,"label":"gtd_calendar"},
                  {"index":5,"uuid":"AI","display":2,"label":"gtd_ai"},
                  {"index":6,"uuid":"OTHER","display":2,"label":"other"},
                  {"index":7,"uuid":"CODE","display":2,"label":"coding_editor_wide"},
                  {"index":8,"uuid":"SANDBOX","display":2,"label":"sandbox_wide"}
                ]'
            case '*'
                echo '[
                  {"index":1,"uuid":"HOME","display":1,"label":""},
                  {"index":2,"uuid":"CONTROL","display":1,"label":"coding_control"},
                  {"index":3,"uuid":"CHAT","display":1,"label":"gtd_chat"},
                  {"index":4,"uuid":"CAL","display":1,"label":"gtd_calendar"},
                  {"index":5,"uuid":"AI","display":2,"label":"gtd_ai"},
                  {"index":6,"uuid":"CODE","display":2,"label":"coding_editor_wide"},
                  {"index":7,"uuid":"SANDBOX","display":2,"label":"sandbox_wide"},
                  {"index":8,"uuid":"OTHER","display":2,"label":"other"}
                ]'
        end
    end

    workspace_verify_mode_space_order wide
    or return 2
    set -g __work_smoke_order_scenario interleaved
    workspace_verify_mode_space_order wide >/dev/null 2>&1
    test $status -ne 0; or return 3

    set -g __work_smoke_order_calls 0
    set -g __work_smoke_verify_calls 0
    set -g __work_smoke_retry_scenario second_pass
    function workspace_order_mode_spaces
        set -g __work_smoke_order_calls (math $__work_smoke_order_calls + 1)
    end
    function workspace_verify_mode_space_order
        set -g __work_smoke_verify_calls (math $__work_smoke_verify_calls + 1)
        if test "$__work_smoke_retry_scenario" = second_pass -a $__work_smoke_verify_calls -eq 2
            return 0
        end
        return 1
    end

    workspace_order_and_verify_mode_spaces wide >/dev/null 2>&1
    or return 4
    test $__work_smoke_order_calls -eq 2 -a $__work_smoke_verify_calls -eq 2
    or return 5

    set -g __work_smoke_order_calls 0
    set -g __work_smoke_verify_calls 0
    set -g __work_smoke_retry_scenario always_fail
    workspace_order_and_verify_mode_spaces wide >/dev/null 2>&1
    test $status -ne 0; or return 6
    test $__work_smoke_order_calls -eq 2 -a $__work_smoke_verify_calls -eq 2
end

function __work_smoke_finalization_finalize
    set -g __work_smoke_finalize_steps
    set -g __work_smoke_finalize_failure none
    set -g __work_smoke_detected_mode wide

    function workspace_detect_display_mode
        echo $__work_smoke_detected_mode
    end
    function resolve_workspace_primary_display
        echo 1
    end
    function workspace_resolve_display_role
        echo 2
    end
    function ws_query_spaces
        if test "$argv[2]" = final_spaces
            echo '[
              {"index":1,"uuid":"HOME","display":1,"label":""},
              {"index":9,"uuid":"TARGET","display":2,"label":"gtd_review_wide"}
            ]'
        else
            echo '[
              {"index":1,"uuid":"HOME","display":1,"label":""},
              {"index":8,"uuid":"TARGET","display":2,"label":"gtd_review_wide"}
            ]'
        end
    end
    function ws_query_current_space
        echo '{"index":8,"uuid":"TARGET"}'
    end
    function workspace_apply_sandbox
        set -ga __work_smoke_finalize_steps sandbox
        test "$__work_smoke_finalize_failure" != sandbox
    end
    function workspace_cleanup_empty_spaces
        set -ga __work_smoke_finalize_steps cleanup
        test "$__work_smoke_finalize_failure" != cleanup
    end
    function workspace_order_and_verify_mode_spaces
        set -ga __work_smoke_finalize_steps order
        test "$__work_smoke_finalize_failure" != order
    end
    function ws_focus_space
        set -ga __work_smoke_finalize_steps focus:$argv[1]
    end

    workspace_finalize_mode wide
    or return 1
    test (string join ' ' -- $__work_smoke_finalize_steps) = 'sandbox cleanup order focus:9'
    or return 2

    set -g __work_smoke_finalize_steps
    set -g __work_smoke_finalize_failure sandbox
    workspace_finalize_mode wide >/dev/null 2>&1
    test $status -ne 0; or return 3
    test (string join ' ' -- $__work_smoke_finalize_steps) = 'sandbox focus:9'
    or return 4

    set -g __work_smoke_finalize_steps
    set -g __work_smoke_finalize_failure order
    workspace_finalize_mode wide >/dev/null 2>&1
    test $status -ne 0; or return 5
    test (string join ' ' -- $__work_smoke_finalize_steps) = 'sandbox cleanup order focus:9'
    or return 6

    set -g __work_smoke_finalize_steps
    set -g __work_smoke_finalize_failure none
    set -g __work_smoke_detected_mode wide
    workspace_finalize_mode auto
    or return 7
    test (string join ' ' -- $__work_smoke_finalize_steps) = 'sandbox cleanup order focus:9'
    or return 8

    set -g __work_smoke_finalize_steps
    set -g __work_smoke_detected_mode solo
    workspace_finalize_mode auto >/dev/null 2>&1
    or return 9
    test (count $__work_smoke_finalize_steps) -eq 0
end

function __work_smoke_finalization_runner
    set -g __work_smoke_runner_body_calls 0
    set -g __work_smoke_runner_final_modes
    set -g __work_smoke_runner_body_status 0
    set -g __work_smoke_runner_final_status 0

    function __work_smoke_runner_leaf
        set -g __work_smoke_runner_body_calls (math $__work_smoke_runner_body_calls + 1)
        return $__work_smoke_runner_body_status
    end
    function __work_smoke_runner_nested
        workspace_run_finalized_entry --mode tall --command __work_smoke_runner_leaf -- $argv
        workspace_run_finalized_entry --mode auto --command __work_smoke_runner_leaf -- $argv
    end
    function workspace_finalize_mode
        set -ga __work_smoke_runner_final_modes $argv[1]
        return $__work_smoke_runner_final_status
    end

    workspace_run_finalized_entry --mode wide --command __work_smoke_runner_leaf --
    or return 1
    test $__work_smoke_runner_body_calls -eq 1; or return 2
    test (string join ' ' -- $__work_smoke_runner_final_modes) = wide; or return 3

    set -g __work_smoke_runner_body_calls 0
    set -g __work_smoke_runner_final_modes
    workspace_run_finalized_entry --mode wide --command __work_smoke_runner_nested --
    or return 4
    test $__work_smoke_runner_body_calls -eq 2; or return 5
    test (string join ' ' -- $__work_smoke_runner_final_modes) = wide; or return 6

    set -g __work_smoke_runner_body_calls 0
    set -g __work_smoke_runner_final_modes
    workspace_run_finalized_entry --mode solo --command __work_smoke_runner_nested --
    or return 7
    test $__work_smoke_runner_body_calls -eq 2; or return 8
    test (count $__work_smoke_runner_final_modes) -eq 0; or return 9

    set -g __work_smoke_runner_body_status 7
    set -g __work_smoke_runner_final_modes
    workspace_run_finalized_entry --mode wide --command __work_smoke_runner_leaf -- >/dev/null 2>&1
    test $status -eq 7; or return 10
    test (string join ' ' -- $__work_smoke_runner_final_modes) = wide; or return 11

    set -g __work_smoke_runner_body_status 0
    set -g __work_smoke_runner_final_status 9
    workspace_run_finalized_entry --mode wide --command __work_smoke_runner_leaf -- >/dev/null 2>&1
    test $status -eq 9; or return 12

    set -g __work_smoke_runner_final_status 0
    set -g __work_smoke_runner_final_modes
    set -l dry_run (workspace_run_finalized_entry --mode tall --command __work_smoke_runner_leaf -- --dry-run)
    string match -q '*finalization_mode=tall*' -- "$dry_run"; or return 13
    string match -q '*finalization_steps=sandbox cleanup order_verify restore_focus*' -- "$dry_run"; or return 14
    test (count $__work_smoke_runner_final_modes) -eq 0; or return 15

    not set -q __WORKSPACE_FINALIZATION_DEPTH; or return 16
    not set -q __WORKSPACE_FINALIZATION_MODE
end

function __work_smoke_finalization_entries
    set -l mappings \
        'work_solo|solo' 'coding_solo|solo' 'gtd_solo_all|solo' \
        'work_wide|wide' 'coding_editor_wide|wide' 'coding_wide|wide' 'research_wide|wide' \
        'office_writing_wide|wide' 'office_slides_wide|wide' 'office_wide|wide' \
        'gtd_support_wide|wide' 'gtd_review_wide|wide' 'gtd_mail_wide|wide' \
        'gtd_meeting_wide|wide' 'gtd_ai_wide|wide' 'gtd_wide|wide' \
        'work_tall|tall' 'coding_editor_tall|tall' 'coding_tall|tall' 'research_tall|tall' \
        'office_writing_tall|tall' 'office_slides_tall|tall' 'office_tall|tall' \
        'gtd_support_tall|tall' 'gtd_review_tall|tall' 'gtd_mail_tall|tall' \
        'gtd_meeting_tall|tall' 'gtd_ai_tall|tall' 'gtd_tall|tall' \
        'coding_control|auto' 'gtd_chat|auto' 'gtd_calendar|auto'

    for mapping in $mappings
        set -l parts (string split '|' -- "$mapping")
        set -l definition (string join \n -- (functions $parts[1]))
        string match -q "*workspace_run_finalized_entry --mode $parts[2]*" -- "$definition"
        or begin
            echo "missing finalization wrapper: $parts[1] mode=$parts[2]" >&2
            return 1
        end
    end

    set -l wide_definition (string join \n -- (functions __work_wide_body))
    set -l tall_definition (string join \n -- (functions __work_tall_body))
    not string match -q '*workspace_order_mode_spaces*' -- "$wide_definition"
    or return 2
    not string match -q '*workspace_order_mode_spaces*' -- "$tall_definition"
end

function work_smoke_finalization --description "Run fixture-only workspace finalization smokes"
    set -l requested $argv
    if test (count $requested) -eq 0
        set -l cases policy selection sandbox cleanup ordering finalize runner entries
        set -l failed 0
        for case_name in $cases
            if set -q WORKSPACE_TEST_SOURCE_ROOT
                set -l child_commands \
                    'set -e WORKSPACE_SKIP_FINALIZATION' \
                    'work_reload >/dev/null' \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_manifest.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_ownership_policy.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_sandbox.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_order_spaces.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_display_roles.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_finalize.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/common/work_entries.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/coding/coding_entries.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/coding/internal/coding_control.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/research/research_entries.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/office/office_entries.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_apply_ai_space.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_chat.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_calendar.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/gtd/gtd_entries.fish\"" \
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/common/work_smoke_finalization.fish\"" \
                    "work_smoke_finalization $case_name"
                set -l child_command (string join '; ' -- $child_commands)
                fish -lc "$child_command"
            else
                fish -lc "set -e WORKSPACE_SKIP_FINALIZATION; work_reload >/dev/null; work_smoke_finalization $case_name"
            end
            or set failed 1
        end
        return $failed
    end

    set -l failed 0
    for case_name in $requested
        switch "$case_name"
            case policy
                __work_smoke_finalization_policy
            case selection
                __work_smoke_finalization_selection
            case sandbox
                __work_smoke_finalization_sandbox
            case cleanup
                __work_smoke_finalization_cleanup
            case ordering
                __work_smoke_finalization_ordering
            case finalize
                __work_smoke_finalization_finalize
            case runner
                __work_smoke_finalization_runner
            case entries
                __work_smoke_finalization_entries
            case '*'
                echo "usage: work_smoke_finalization [policy|selection|sandbox|cleanup|ordering|finalize|runner|entries ...]" >&2
                return 2
        end

        if test $status -eq 0
            echo "OK      finalization $case_name"
        else
            echo "FAIL    finalization $case_name" >&2
            set failed 1
        end
    end

    return $failed
end

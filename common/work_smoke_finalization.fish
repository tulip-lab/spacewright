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

    set -g __work_smoke_sandbox_queries 0
    set -g __work_smoke_sandbox_create
    set -g __work_smoke_sandbox_prepare
    set -g __work_smoke_sandbox_moves
    set -g __work_smoke_sandbox_yabai
    workspace_apply_sandbox --mode solo --home-space 1 --display 1
    or return 20
    test "$__work_smoke_sandbox_create" = 'sandbox_solo 1'; or return 21
    test "$__work_smoke_sandbox_prepare" = '8 sandbox_solo bsp'; or return 22
    test "$__work_smoke_sandbox_moves" = '8 11 17'; or return 23

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
    set -g __work_smoke_cleanup_window_queries 0

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
          {"index":7,"uuid":"ONLY","display":3,"label":""},
          {"index":8,"uuid":"OFFICE_GHOST","display":2,"label":""},
          {"index":9,"uuid":"OTHER_IMMOVABLE","display":2,"label":""},
          {"index":10,"uuid":"EMPTY_CONTROL","display":1,"label":"coding_control"}
        ]'
    end

    function ws_query_windows
        set -g __work_smoke_cleanup_window_queries (math $__work_smoke_cleanup_window_queries + 1)
        if test "$__work_smoke_cleanup_scenario" = settled -a $__work_smoke_cleanup_window_queries -gt 1
            echo '[
              {"id":21,"space":2,"is-sticky":false},
              {"id":30,"space":3,"is-sticky":false}
            ]'
            return 0
        end
        echo '[
          {"id":21,"space":2,"is-sticky":false},
          {"id":50,"space":5,"is-sticky":true},
          {"id":60,"space":6,"is-sticky":false},
          {"id":80,"app":"Microsoft Word","title":"","role":"","subrole":"","space":8,"can-move":false,"is-sticky":false},
          {"id":90,"app":"Terminal","title":"","role":"","subrole":"","space":9,"can-move":false,"is-sticky":false}
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

    set -l occupant_windows (ws_query_windows | workspace_space_occupant_windows_json)
    or return 7
    set -l occupant_ids (echo $occupant_windows | ws_jq -r '.[].id')
    or return 8
    test (string join ' ' -- $occupant_ids) = '21 60 90'
    or return 9

    workspace_cleanup_empty_spaces --home-uuid HOME --focus-uuid FOCUSED
    or return 1
    test (string join ' ' -- $__work_smoke_cleanup_destroyed) = '8 5 4 3'
    or return 2
    test (string join ' ' -- $__work_smoke_cleanup_focused) = '6'
    or return 3
    not contains -- 1 $__work_smoke_cleanup_destroyed; or return 4
    not contains -- 7 $__work_smoke_cleanup_destroyed; or return 5
    not contains -- 10 $__work_smoke_cleanup_destroyed; or return 12

    set -g __work_smoke_cleanup_scenario settled
    set -g __work_smoke_cleanup_destroyed
    set -g __work_smoke_cleanup_window_queries 0
    workspace_cleanup_empty_spaces --home-uuid HOME --focus-uuid FOCUSED
    or return 10
    not contains -- 3 $__work_smoke_cleanup_destroyed
    or return 11

    set -g __work_smoke_cleanup_scenario failure
    set -g __work_smoke_cleanup_destroyed
    workspace_cleanup_empty_spaces --home-uuid HOME --focus-uuid FOCUSED >/dev/null 2>&1
    test $status -ne 0; or return 6
    test (count $__work_smoke_cleanup_destroyed) -eq 0
end

function __work_smoke_finalization_ordering
    set -l solo_dry_run (workspace_order_mode_spaces --dry-run solo)
    string match -q '*primary=coding_control,gtd_chat,gtd_calendar,gtd_ai,coding_editor_solo,research_solo,gtd_support_solo,gtd_review_solo,gtd_mail_solo,gtd_meeting_solo,sandbox_solo*' -- "$solo_dry_run"
    or return 10

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
            case empty_managed
                echo '[
                  {"index":1,"uuid":"HOME","display":1,"label":""},
                  {"index":2,"uuid":"CONTROL","display":1,"label":"coding_control"},
                  {"index":3,"uuid":"OTHER","display":2,"label":""}
                ]'
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
    set -g __work_smoke_order_scenario empty_managed
    workspace_verify_mode_space_order wide
    or return 7
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

function __work_smoke_finalization_diagnostics
    function ws_query_displays
        echo '[]'
    end
    function ws_query_spaces
        echo '[{"index":8,"uuid":"OFFICE_GHOST","display":2,"label":"","windows":[80]}]'
    end
    function ws_query_windows
        echo '[{"id":80,"app":"Microsoft Word","title":"","role":"","subrole":"","space":8,"can-move":false,"is-sticky":false}]'
    end
    function work_display_health
    end
    function workspace_space_order_health
    end
    function ws_query_current_display
        echo '{}'
    end
    function ws_query_current_space
        echo '{}'
    end
    function work_bad_windows
    end

    set -l output (string join \n -- (work_diagnostics))
    string match -q '*===== EMPTY UNLABELED SPACES =====*"index": 8*' -- "$output"
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
    workspace_finalize_mode auto
    or return 9
    test "$(string join ' ' -- $__work_smoke_finalize_steps)" = 'sandbox cleanup order focus:9'
end

function __work_smoke_finalization_runner
    set -g __work_smoke_runner_body_calls 0
    set -g __work_smoke_runner_final_modes
    set -g __work_smoke_runner_body_status 0
    set -g __work_smoke_runner_final_status 0
    set -g __work_smoke_runner_restart_on_call 0
    set -g __work_smoke_runner_replay_restart_disabled 0
    set -g __WORKSPACE_YABAI_RESTART_GENERATION 0

    function __work_smoke_runner_leaf
        set -g __work_smoke_runner_body_calls (math $__work_smoke_runner_body_calls + 1)
        if test "$__work_smoke_runner_body_calls" -eq "$__work_smoke_runner_restart_on_call"
            set -g __WORKSPACE_YABAI_RESTART_GENERATION (math $__WORKSPACE_YABAI_RESTART_GENERATION + 1)
        else if test "$__work_smoke_runner_restart_on_call" -gt 0
            and test "$__work_smoke_runner_body_calls" -gt "$__work_smoke_runner_restart_on_call"
            and test "$WORKSPACE_DISABLE_YABAI_AUTO_RESTART" = 1
            set -g __work_smoke_runner_replay_restart_disabled 1
        end
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
    test "$(string join ' ' -- $__work_smoke_runner_final_modes)" = solo; or return 9

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

    set -g __work_smoke_runner_body_calls 0
    set -g __work_smoke_runner_final_modes
    set -g __work_smoke_runner_restart_on_call 1
    set -g __work_smoke_runner_replay_restart_disabled 0
    set -g __WORKSPACE_YABAI_RESTART_GENERATION 0
    workspace_run_finalized_entry --mode wide --command __work_smoke_runner_leaf -- >/dev/null 2>&1
    or return 16
    test $__work_smoke_runner_body_calls -eq 2; or return 17
    test $__work_smoke_runner_replay_restart_disabled -eq 1; or return 18
    test (string join ' ' -- $__work_smoke_runner_final_modes) = wide; or return 19

    not set -q __WORKSPACE_FINALIZATION_DEPTH; or return 20
    not set -q __WORKSPACE_FINALIZATION_MODE
end

function __work_smoke_labeled_space_creation
    set -g __work_smoke_labeled_scenario reuse
    set -g __work_smoke_labeled_create_calls 0
    set -g __work_smoke_labeled_after_create_queries 0

    function ws_query_spaces
        set -l phase $argv[2]

        if test "$__work_smoke_labeled_scenario" = delayed_create
            if string match -q 'after_create_*' -- "$phase"
                set -g __work_smoke_labeled_after_create_queries (math $__work_smoke_labeled_after_create_queries + 1)
            end

            if test "$__work_smoke_labeled_after_create_queries" -ge 3
                echo '[{"index":8,"uuid":"old","display":2,"label":"","is-visible":true,"has-focus":true},{"index":9,"uuid":"new","display":2,"label":"","is-visible":false,"has-focus":false}]'
            else
                echo '[{"index":8,"uuid":"old","display":2,"label":"","is-visible":true,"has-focus":true}]'
            end
            return 0
        end

        echo '[{"index":8,"uuid":"occupied","display":2,"label":"","is-visible":true,"has-focus":true},{"index":9,"uuid":"empty","display":2,"label":"","is-visible":false,"has-focus":false}]'
    end

    function ws_query_windows
        if test "$__work_smoke_labeled_scenario" = delayed_create
            echo '[{"id":1,"space":8,"is-sticky":false}]'
        else
            echo '[{"id":1,"space":8,"is-sticky":false},{"id":2,"space":9,"is-sticky":true}]'
        end
    end

    function ws_yabai
        if test "$argv[1]" = -m -a "$argv[2]" = space -a "$argv[3]" = --create
            set -g __work_smoke_labeled_create_calls (math $__work_smoke_labeled_create_calls + 1)
            return 0
        end
        return 1
    end

    function sleep
    end

    test (find_or_create_labeled_space test_wide 2) = 9
    or return 1
    test $__work_smoke_labeled_create_calls -eq 0
    or return 2

    set -g __work_smoke_labeled_scenario delayed_create
    set -g __work_smoke_labeled_after_create_queries 0
    test (find_or_create_labeled_space test_wide 2) = 9
    or return 3
    test $__work_smoke_labeled_create_calls -eq 1
    or return 4
    test $__work_smoke_labeled_after_create_queries -eq 3
end

function __work_smoke_finalization_entries
    functions -q workspace_finalized_entry_rows
    or begin
        echo "missing finalized-entry manifest" >&2
        return 1
    end

    set -l mappings (workspace_finalized_entry_rows)
    test (count $mappings) -gt 0
    or return 2

    for mapping in $mappings
        set -l parts (string split \t -- "$mapping")
        set -l definition (string join \n -- (functions $parts[1]))
        string match -q "*workspace_run_finalized_entry --mode $parts[2]*" -- "$definition"
        or begin
            echo "missing finalization wrapper: $parts[1] mode=$parts[2]" >&2
            return 3
        end
    end

    set -l wide_definition (string join \n -- (functions __work_wide_body))
    set -l tall_definition (string join \n -- (functions __work_tall_body))
    not string match -q '*workspace_order_mode_spaces*' -- "$wide_definition"
    or return 4
    not string match -q '*workspace_order_mode_spaces*' -- "$tall_definition"
end

function __work_smoke_staged_top_level
    set -g __work_smoke_staged_calls
    set -g __work_smoke_staged_fail ""

    for command_name in \
            coding_solo research_solo gtd_solo_all \
            research_wide office_wide gtd_support_wide gtd_review_wide coding_editor_wide \
            gtd_mail_wide gtd_meeting_wide \
            research_tall office_tall gtd_support_tall gtd_review_tall coding_editor_tall \
            gtd_mail_tall gtd_meeting_tall gtd_chat gtd_calendar coding_control
        eval "function $command_name; set -ga __work_smoke_staged_calls $command_name; if test \"\$__work_smoke_staged_fail\" = \"$command_name\"; return 1; end; end"
    end

    function workspace_reconcile_primary_fixed_spaces
        set -ga __work_smoke_staged_calls reconcile
    end

    function workspace_run_step
        set -e argv[1]
        $argv
    end

    function workspace_finalize_mode
        set -ga __work_smoke_staged_calls finalize:$argv[1]
    end

    set -e WORKSPACE_SKIP_FINALIZATION
    work_solo
    or return 1
    test (string join , -- $__work_smoke_staged_calls) = \
        "coding_solo,research_solo,gtd_solo_all,reconcile,finalize:solo"
    or return 2

    set -g __work_smoke_staged_calls
    work_wide
    or return 3
    test (string join , -- $__work_smoke_staged_calls) = \
        "research_wide,office_wide,gtd_support_wide,gtd_review_wide,coding_editor_wide,gtd_mail_wide,gtd_meeting_wide,gtd_chat,gtd_calendar,coding_control,reconcile,finalize:wide"
    or return 4

    set -g __work_smoke_staged_calls
    work_tall
    or return 5
    test (string join , -- $__work_smoke_staged_calls) = \
        "research_tall,office_tall,gtd_support_tall,gtd_review_tall,coding_editor_tall,gtd_mail_tall,gtd_meeting_tall,gtd_chat,gtd_calendar,coding_control,reconcile,finalize:tall"
    or return 6

    set -g __work_smoke_staged_calls
    set -g __work_smoke_staged_fail gtd_review_wide
    work_wide
    set -l failed_status $status
    test $failed_status -ne 0
    or return 7
    test "$__work_smoke_staged_calls[-1]" = finalize:wide
end

function __work_smoke_primary_fixed_separation
    if set -q WORKSPACE_TEST_SOURCE_ROOT
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_primary_fixed_separation.fish"
    else
        source ~/.config/fish/functions/workspace/common/workspace_primary_fixed_separation.fish
    end

    set -g __work_smoke_primary_fixture valid
    set -g __work_smoke_primary_calls
    set -g __work_smoke_primary_space_queries 0
    set -g __work_smoke_primary_window_queries 0

    function ws_query_spaces
        set -g __work_smoke_primary_space_queries (math $__work_smoke_primary_space_queries + 1)
        switch $__work_smoke_primary_fixture
            case missing missing_with_apps
                printf '%s\n' '[{"index":1,"uuid":"HOME","display":1,"label":""}]'
            case shared
                printf '%s\n' '[{"index":2,"uuid":"MIXED","display":1,"label":"gtd_chat"},{"index":2,"uuid":"MIXED","display":1,"label":"coding_control"}]'
            case duplicate
                printf '%s\n' '[{"index":2,"uuid":"CHAT-A","display":1,"label":"gtd_chat"},{"index":3,"uuid":"CHAT-B","display":1,"label":"gtd_chat"}]'
            case misplaced
                printf '%s\n' '[{"index":2,"uuid":"CHAT","display":1,"label":"gtd_chat"},{"index":3,"uuid":"CONTROL","display":2,"label":"coding_control"}]'
            case '*'
                printf '%s\n' '[{"index":2,"uuid":"CHAT","display":1,"label":"gtd_chat"},{"index":3,"uuid":"CONTROL","display":1,"label":"coding_control"}]'
        end
    end

    function ws_query_windows
        set -g __work_smoke_primary_window_queries (math $__work_smoke_primary_window_queries + 1)
        switch $__work_smoke_primary_fixture
            case missing
                printf '%s\n' '[]'
            case missing_with_apps
                printf '%s\n' '[{"id":11,"app":"WeChat","space":1,"is-sticky":false},{"id":12,"app":"Warp","space":1,"is-sticky":false}]'
            case cross_owned persistent reconcile_failure
                printf '%s\n' '[{"id":11,"app":"WeChat","space":2,"is-sticky":false},{"id":12,"app":"Warp","space":2,"is-sticky":false},{"id":13,"app":"SmartGit","space":3,"is-sticky":false}]'
            case shared duplicate
                printf '%s\n' '[{"id":11,"app":"WeChat","space":2,"is-sticky":false},{"id":12,"app":"Warp","space":2,"is-sticky":false}]'
            case '*'
                printf '%s\n' '[{"id":11,"app":"WeChat","space":2,"is-sticky":false},{"id":12,"app":"FaceTime","space":2,"is-sticky":true},{"id":13,"app":"Warp","space":3,"is-sticky":false},{"id":14,"app":"KeePassX","space":3,"is-sticky":false}]'
        end
    end

    function gtd_chat
        set -ga __work_smoke_primary_calls gtd_chat
        if test "$__work_smoke_primary_fixture" = reconcile_failure
            set -g __work_smoke_primary_fixture valid
            return 1
        end
        if test "$__work_smoke_primary_fixture" != persistent
            set -g __work_smoke_primary_fixture valid
        end
    end

    function coding_control
        set -ga __work_smoke_primary_calls coding_control
    end

    function resolve_workspace_primary_display
        echo 1
    end

    workspace_verify_primary_fixed_separation
    or return 1
    test $__work_smoke_primary_space_queries -eq 1
    and test $__work_smoke_primary_window_queries -eq 1
    or return 2

    set -g __work_smoke_primary_fixture missing
    workspace_verify_primary_fixed_separation
    or return 3

    for invalid_fixture in missing_with_apps shared duplicate misplaced cross_owned
        set -g __work_smoke_primary_fixture $invalid_fixture
        workspace_verify_primary_fixed_separation >/dev/null 2>&1
        and return 4
    end

    set -g __work_smoke_primary_fixture cross_owned
    set -g __work_smoke_primary_calls
    workspace_reconcile_primary_fixed_spaces
    or return 5
    test (string join , -- $__work_smoke_primary_calls) = gtd_chat,coding_control
    or return 6

    set -g __work_smoke_primary_fixture persistent
    set -g __work_smoke_primary_calls
    workspace_reconcile_primary_fixed_spaces >/dev/null 2>&1
    and return 7
    test (string join , -- $__work_smoke_primary_calls) = gtd_chat,coding_control
    or return 8

    set -g __work_smoke_primary_fixture reconcile_failure
    set -g __work_smoke_primary_calls
    workspace_reconcile_primary_fixed_spaces >/dev/null 2>&1
    and return 9
    test (string join , -- $__work_smoke_primary_calls) = gtd_chat,coding_control
end

function work_smoke_finalization --description "Run fixture-only workspace finalization smokes"
    set -l requested $argv
    if test (count $requested) -eq 0
        set -l cases policy selection sandbox cleanup ordering diagnostics finalize runner labeled_space entries staged primary_separation
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
                    "source \"$WORKSPACE_TEST_SOURCE_ROOT/common/work_diagnostics.fish\"" \
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
            case diagnostics
                __work_smoke_finalization_diagnostics
            case finalize
                __work_smoke_finalization_finalize
            case runner
                __work_smoke_finalization_runner
            case labeled_space
                __work_smoke_labeled_space_creation
            case entries
                __work_smoke_finalization_entries
            case staged
                __work_smoke_staged_top_level
            case primary_separation
                __work_smoke_primary_fixed_separation
            case '*'
                echo "usage: work_smoke_finalization [policy|selection|sandbox|cleanup|ordering|diagnostics|finalize|runner|labeled_space|entries|staged|primary_separation ...]" >&2
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

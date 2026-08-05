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

function work_smoke_finalization --description "Run fixture-only workspace finalization smokes"
    set -l requested $argv
    if test (count $requested) -eq 0
        set requested policy selection sandbox
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
            case '*'
                echo "usage: work_smoke_finalization [policy|selection|sandbox ...]" >&2
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

function work_smoke --description "Run read-only workspace smoke checks for helper wiring and dry-run paths"
    set -l failed 0
    set -lx WORKSPACE_SKIP_FINALIZATION 1
    set -l had_fish_function 0

    if functions -q fish
        set had_fish_function 1
        functions -c fish __spacewright_saved_fish_function
    end

    set -l smoke_source_root "$SPACEWRIGHT_ROOT"
    set -l smoke_package_root "$SPACEWRIGHT_PACKAGE_ROOT"
    set -l smoke_config_root "$SPACEWRIGHT_CONFIG_ROOT"
    if set -q WORKSPACE_TEST_SOURCE_ROOT
        set smoke_source_root "$WORKSPACE_TEST_SOURCE_ROOT"
        set smoke_package_root (path dirname (path dirname "$smoke_source_root"))
        set smoke_config_root "$smoke_package_root/tests/fixtures/xdg-empty/spacewright"
        set -lx fish_function_path "$smoke_source_root/common" $fish_function_path
        set -lx XDG_CONFIG_HOME "$smoke_package_root/tests/fixtures/xdg-empty"
        set -lx SPACEWRIGHT_CONFIG_ROOT "$smoke_config_root"
    end

    set -l smoke_fish_binary (command -s fish)
    function fish --inherit-variable smoke_fish_binary --inherit-variable smoke_source_root --inherit-variable smoke_package_root --inherit-variable smoke_config_root
        if test "$argv[1]" = -lc; and test -n "$smoke_source_root"
            set -l escaped_source_root (string escape -- "$smoke_source_root")
            set -l escaped_package_root (string escape -- "$smoke_package_root")
            set -l escaped_config_root (string escape -- "$smoke_config_root")
            set argv[2] "set -gx SPACEWRIGHT_PACKAGE_ROOT $escaped_package_root; set -gx SPACEWRIGHT_ROOT $escaped_source_root; set -gx SPACEWRIGHT_CONFIG_ROOT $escaped_config_root; source $escaped_source_root/common/spacewright_paths.fish; source $escaped_source_root/common/work_reload.fish; $argv[2]"
        end
        command $smoke_fish_binary $argv
    end

    echo "===== WORKSPACE SMOKE ====="

    work_reload >/dev/null
    or set failed 1

    if set -q WORKSPACE_TEST_SOURCE_ROOT
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_manifest.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_ownership_policy.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_sandbox.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_order_spaces.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_display_roles.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_finalize.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/work_entries.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/work_audit.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/common/work_smoke_finalization.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/coding/coding_entries.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/coding/internal/coding_control.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/research/research_entries.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/office/office_entries.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_apply_ai_space.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_chat.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_calendar.fish"
        source "$WORKSPACE_TEST_SOURCE_ROOT/gtd/gtd_entries.fish"
    end

    work_command_check >/tmp/work-command-check.out
    if test $status -eq 0
        echo "OK      command check"
    else
        echo "FAIL    command check"
        cat /tmp/work-command-check.out
        set failed 1
    end

    if workspace_config_check
        echo "OK      configured workspace schema"
    else
        echo "FAIL    configured workspace schema"
        set failed 1
    end

    set -l configured_plan (workspace_config_plan coding_editor_wide | string collect)
    if test $status -eq 0; and printf "%s\n" "$configured_plan" | jq -e '.kind=="workspace" and .mutates==false and .label=="coding_editor_wide"' >/dev/null
        echo "OK      configured workspace read-only plan"
    else
        echo "FAIL    configured workspace read-only plan"
        set failed 1
    end

    set -l app_keys \
        code claude chatgpt obsidian zotero thunderbird word powerpoint outlook zoom teams dia finder preview notes \
        calendar reminders wechat keybase messages dingtalk whatsapp facetime warp smartgit keepassx flclash thaw portfolio_performance

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

    set -l gtd_chat_dry_run (gtd_chat --dry-run)
    if string match -q "*apps=WeChat,Keybase,DingTalk|钉钉,Messages,WhatsApp,FaceTime*" -- "$gtd_chat_dry_run"
        echo "OK      GTD chat FaceTime dry-run"
    else
        echo "FAIL    GTD chat FaceTime dry-run"
        printf "%s\n" $gtd_chat_dry_run
        set failed 1
    end

    set -l gtd_chat_facetime_smoke '
        work_reload >/dev/null

        set -g __work_smoke_chat_moves
        set -g __work_smoke_chat_windows

        function ws_query_windows
            printf "%s\n" "[
                {\"id\":61,\"app\":\"FaceTime\",\"title\":\"FaceTime\",\"space\":9,\"display\":1,\"can-move\":true,\"is-minimized\":false}
            ]"
        end

        function workspace_find_app_key_window
            argparse "app-key=" "caller=" "space=" no-refresh target-only quiet-unmovable -- $argv
            if test "$_flag_app_key" = facetime
                echo 61
            end
        end

        function resolve_workspace_primary_display
            echo 1
        end

        function find_or_create_labeled_space
            echo 9
        end

        function workspace_retarget_contaminated_space
            echo 9
        end

        function workspace_focus_labeled_space
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_chat_moves (string join " " -- $argv)
        end

        function ws_window
            set -ga __work_smoke_chat_windows (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_chat
        or exit 1

        contains -- "9 61" $__work_smoke_chat_moves
        or exit 2

        contains -- "61 --move abs:458:190" $__work_smoke_chat_windows
        or exit 3

        contains -- "61 --resize abs:885:560" $__work_smoke_chat_windows
        or exit 4
    '
    fish -lc "$gtd_chat_facetime_smoke" >/tmp/work-gtd-chat-facetime-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      GTD chat FaceTime capture and centered layout"
    else
        echo "FAIL    GTD chat FaceTime capture and centered layout"
        cat /tmp/work-gtd-chat-facetime-smoke.out
        set failed 1
    end

    if begin
            workspace_app_names codex >/dev/null
        end 2>/dev/null
        echo "FAIL    retired codex app key still registered"
        set failed 1
    else
        echo "OK      retired codex app key"
    end

    set -l coding_control_dry_run (coding_control --dry-run)
    if string match -q "*apps=Warp,SmartGit,KeePassXC,FlClash|Thaw,Portfolio Performance*" -- "$coding_control_dry_run"
        echo "OK      coding control Portfolio Performance dry-run"
    else
        echo "FAIL    coding control Portfolio Performance dry-run"
        printf "%s\n" $coding_control_dry_run
        set failed 1
    end

    set -l coding_editor_wide_dry_run (coding_editor_wide --dry-run)
    set -l coding_editor_tall_dry_run (coding_editor_tall --dry-run)
    set -l coding_editor_solo_dry_run (coding_editor_solo --dry-run)
    if string match -q "*primary_app=Code*" -- "$coding_editor_wide_dry_run"
            and string match -q "*helper_app=ChatGPT*" -- "$coding_editor_wide_dry_run"
            and string match -q "*primary_grid=1:3:1:0:2:1*" -- "$coding_editor_wide_dry_run"
            and string match -q "*primary_alone_grid=1:1:0:0:1:1*" -- "$coding_editor_wide_dry_run"
            and string match -q "*helper_grid=1:3:0:0:1:1*" -- "$coding_editor_wide_dry_run"
            and string match -q "*primary_app=Code*" -- "$coding_editor_tall_dry_run"
            and string match -q "*helper_app=ChatGPT*" -- "$coding_editor_tall_dry_run"
            and string match -q "*primary_grid=2:1:0:1:1:1*" -- "$coding_editor_tall_dry_run"
            and string match -q "*primary_alone_grid=1:1:0:0:1:1*" -- "$coding_editor_tall_dry_run"
            and string match -q "*helper_grid=2:1:0:0:1:1*" -- "$coding_editor_tall_dry_run"
            and string match -q "*primary_grid=1:1:0:0:1:1*" -- "$coding_editor_solo_dry_run"
            and not string match -q "*helper_app=*" -- "$coding_editor_solo_dry_run"
        echo "OK      coding editor VS Code/ChatGPT layouts"
    else
        echo "FAIL    coding editor VS Code/ChatGPT layouts"
        printf "%s\n" $coding_editor_wide_dry_run
        printf "%s\n" $coding_editor_tall_dry_run
        printf "%s\n" $coding_editor_solo_dry_run
        set failed 1
    end

    set -l research_solo_dry_run (research_solo --dry-run)
    if string match -q "*primary_app=Zotero*" -- "$research_solo_dry_run"
            and string match -q "*helper_app=Claude*" -- "$research_solo_dry_run"
            and not string match -q "*helper_app=ChatGPT*" -- "$research_solo_dry_run"
        echo "OK      research solo Zotero/Claude layout"
    else
        echo "FAIL    research solo Zotero/Claude layout"
        printf "%s\n" $research_solo_dry_run
        set failed 1
    end

    set -l gtd_ai_solo_dry_run (gtd_ai_solo --dry-run)
    set -l gtd_ai_wide_dry_run (gtd_ai_wide --dry-run)
    set -l gtd_ai_tall_dry_run (gtd_ai_tall --dry-run)
    if string match -q "*apps=Hermes,ChatGPT,Obsidian,Notes*" -- "$gtd_ai_wide_dry_run"
            and string match -q "*hermes_grid=1:4:1:0:2:1*" -- "$gtd_ai_wide_dry_run"
            and string match -q "*chatgpt_grid=1:4:3:0:1:1*" -- "$gtd_ai_wide_dry_run"
            and string match -q "*obsidian_grid=2:4:0:1:1:1*" -- "$gtd_ai_wide_dry_run"
            and string match -q "*notes_grid=2:4:0:0:1:1*" -- "$gtd_ai_wide_dry_run"
            and string match -q "*hermes_grid=4:2:0:0:2:2*" -- "$gtd_ai_tall_dry_run"
            and string match -q "*chatgpt_grid=4:2:0:2:2:1*" -- "$gtd_ai_tall_dry_run"
            and string match -q "*obsidian_grid=4:2:0:3:1:1*" -- "$gtd_ai_tall_dry_run"
            and string match -q "*notes_grid=4:2:1:3:1:1*" -- "$gtd_ai_tall_dry_run"
            and string match -q "*hermes_grid=2:3:0:0:3:1*" -- "$gtd_ai_solo_dry_run"
            and string match -q "*chatgpt_grid=2:3:0:1:1:1*" -- "$gtd_ai_solo_dry_run"
            and string match -q "*obsidian_grid=2:3:1:1:1:1*" -- "$gtd_ai_solo_dry_run"
            and string match -q "*notes_grid=2:3:2:1:1:1*" -- "$gtd_ai_solo_dry_run"
            and not string match -q "*codex_grid=*" -- "$gtd_ai_wide_dry_run"
        echo "OK      GTD AI Hermes-first mode layouts"
    else
        echo "FAIL    GTD AI Hermes-first mode layouts"
        printf "%s\n" $gtd_ai_solo_dry_run
        printf "%s\n" $gtd_ai_wide_dry_run
        printf "%s\n" $gtd_ai_tall_dry_run
        set failed 1
    end

    set -l gtd_ai_hermes_space_fallback_smoke '
        work_reload >/dev/null

        set -g __work_smoke_ai_fallback_args ""
        set -g __work_smoke_ai_eviction_args ""
        set -g __work_smoke_ai_capture_spaces
        set -g __work_smoke_ai_bounds ""

        function workspace_run_cleanup_specs
        end

        function workspace_resolve_display_role
            echo 2
        end

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 30, \"app\": \"Hermes\", \"space\": 6, \"display\": 1, \"can-move\": false, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Hermes\"}
            ]"
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

        function workspace_focus_space_fallback
            set -g __work_smoke_ai_fallback_args (string join " " -- $argv)
            echo 6
        end

        function workspace_evict_non_owned_windows_from_space
            set -g __work_smoke_ai_eviction_args (string join " " -- $argv)
        end

        function workspace_capture_app_window
            argparse "app-key=" "caller=" "space=" -- $argv
            set -ga __work_smoke_ai_capture_spaces "$_flag_app_key:$_flag_space"
            switch "$_flag_app_key"
                case chatgpt
                    echo 31
                case obsidian
                    echo 32
                case notes
                    echo 33
            end
        end

        function workspace_apply_app_key_grid_bounds
            set -g __work_smoke_ai_bounds (string join " " -- $argv)
        end

        function ws_window
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_ai_space \
            --label gtd_ai \
            --display wide \
            --hermes-grid 1:4:1:0:2:1 \
            --chatgpt-grid 1:4:3:0:1:1 \
            --obsidian-grid 2:4:0:1:1:1 \
            --notes-grid 2:4:0:0:1:1
        or exit 1

        string match -q "*--space 6*" -- "$__work_smoke_ai_fallback_args"
        or exit 2

        string match -q "*--source-display 1*" -- "$__work_smoke_ai_fallback_args"
        or exit 3

        string match -q "*--target-display 2*" -- "$__work_smoke_ai_fallback_args"
        or exit 4

        string match -q "*--space 6*" -- "$__work_smoke_ai_eviction_args"
        or exit 5

        contains -- chatgpt:6 $__work_smoke_ai_capture_spaces
        and contains -- obsidian:6 $__work_smoke_ai_capture_spaces
        and contains -- notes:6 $__work_smoke_ai_capture_spaces
        or exit 6

        string match -q "*--app-key hermes*" -- "$__work_smoke_ai_bounds"
        and string match -q "*--grid 1:4:1:0:2:1*" -- "$__work_smoke_ai_bounds"
        or exit 7
    '
    fish -lc "$gtd_ai_hermes_space_fallback_smoke" >/tmp/work-gtd-ai-hermes-space-fallback-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      GTD AI Hermes space fallback"
    else
        echo "FAIL    GTD AI Hermes space fallback"
        cat /tmp/work-gtd-ai-hermes-space-fallback-smoke.out
        set failed 1
    end

    set -l gtd_review_wide_dry_run (gtd_review_wide --dry-run)
    set -l gtd_review_tall_dry_run (gtd_review_tall --dry-run)
    set -l gtd_review_solo_dry_run (gtd_review_solo --dry-run)
    if string match -q "*apps=Finder,Preview,Notes,ChatGPT,Obsidian*" -- "$gtd_review_wide_dry_run"
            and string match -q "*finder_grid=2:16:0:0:4:2*" -- "$gtd_review_wide_dry_run"
            and string match -q "*preview_grid=2:16:4:0:6:2*" -- "$gtd_review_wide_dry_run"
            and string match -q "*obsidian_grid=2:16:10:0:6:1*" -- "$gtd_review_wide_dry_run"
            and string match -q "*assistant_app=chatgpt*" -- "$gtd_review_wide_dry_run"
            and string match -q "*assistant_grid=2:16:10:1:3:1*" -- "$gtd_review_wide_dry_run"
            and string match -q "*notes_grid=2:16:13:1:3:1*" -- "$gtd_review_wide_dry_run"
            and string match -q "*preview_grid=4:2:0:0:2:2*" -- "$gtd_review_tall_dry_run"
            and string match -q "*finder_grid=4:2:0:2:1:1*" -- "$gtd_review_tall_dry_run"
            and string match -q "*obsidian_grid=4:2:1:2:1:1*" -- "$gtd_review_tall_dry_run"
            and string match -q "*assistant_grid=4:2:0:3:1:1*" -- "$gtd_review_tall_dry_run"
            and string match -q "*notes_grid=4:2:1:3:1:1*" -- "$gtd_review_tall_dry_run"
            and not string match -q "*obsidian_grid=*" -- "$gtd_review_solo_dry_run"
            and not string match -q "*Obsidian*" -- "$gtd_review_solo_dry_run"
        echo "OK      GTD review wide/tall Obsidian layouts"
    else
        echo "FAIL    GTD review wide/tall Obsidian layouts"
        printf "%s\n" $gtd_review_wide_dry_run
        printf "%s\n" $gtd_review_tall_dry_run
        printf "%s\n" $gtd_review_solo_dry_run
        set failed 1
    end

    set -l gtd_meeting_wide_dry_run (gtd_meeting_wide --dry-run)
    if string match -q "*apps=zoom.us|Zoom,Microsoft Teams|MSTeams*" -- "$gtd_meeting_wide_dry_run"
            and string match -q "*zoom_grid=1:2:0:0:1:1*" -- "$gtd_meeting_wide_dry_run"
            and string match -q "*teams_grid=1:2:1:0:1:1*" -- "$gtd_meeting_wide_dry_run"
            and not string match -q "*outlook_grid=*" -- "$gtd_meeting_wide_dry_run"
        echo "OK      GTD meeting wide Zoom/Teams grid"
    else
        echo "FAIL    GTD meeting wide Zoom/Teams grid"
        printf "%s\n" $gtd_meeting_wide_dry_run
        set failed 1
    end

    set -l gtd_mail_wide_dry_run (gtd_mail_wide --dry-run)
    if string match -q "*primary_app=Thunderbird*" -- "$gtd_mail_wide_dry_run"
            and string match -q "*helper_app=Microsoft Outlook*" -- "$gtd_mail_wide_dry_run"
            and string match -q "*primary_grid=1:2:1:0:1:1*" -- "$gtd_mail_wide_dry_run"
            and string match -q "*helper_grid=1:2:0:0:1:1*" -- "$gtd_mail_wide_dry_run"
        echo "OK      GTD mail wide Outlook helper grid"
    else
        echo "FAIL    GTD mail wide Outlook helper grid"
        printf "%s\n" $gtd_mail_wide_dry_run
        set failed 1
    end

    set -l workspace_observability_smoke '
        work_reload >/dev/null

        set -g __work_smoke_observation_fixture meeting_ok
        set -g __work_smoke_observation_display_queries 0
        set -g __work_smoke_observation_space_queries 0
        set -g __work_smoke_observation_window_queries 0
        set -g __work_smoke_observation_mutations 0

        function ws_query_displays
            set -g __work_smoke_observation_display_queries (math $__work_smoke_observation_display_queries + 1)
            printf "%s\n" "[
                {\"index\":1,\"uuid\":\"primary\",\"frame\":{\"x\":0,\"y\":0,\"w\":1800,\"h\":1169}},
                {\"index\":2,\"uuid\":\"external-wide\",\"frame\":{\"x\":-3062,\"y\":-594,\"w\":3062,\"h\":1282}}
            ]"
        end

        function ws_query_spaces
            set -g __work_smoke_observation_space_queries (math $__work_smoke_observation_space_queries + 1)
            switch "$__work_smoke_observation_fixture"
                case meeting_ok meeting_bad
                    printf "%s\n" "[
                        {\"index\":4,\"display\":1,\"label\":\"coding_control\",\"windows\":[]},
                        {\"index\":8,\"display\":2,\"label\":\"gtd_meeting_wide\",\"windows\":[41,51]}
                    ]"
                case coding
                    printf "%s\n" "[
                        {\"index\":4,\"display\":1,\"label\":\"coding_control\",\"windows\":[21]},
                        {\"index\":6,\"display\":1,\"label\":\"\",\"windows\":[22]}
                    ]"
            end
        end

        function ws_query_windows
            set -g __work_smoke_observation_window_queries (math $__work_smoke_observation_window_queries + 1)
            switch "$__work_smoke_observation_fixture"
                case meeting_ok
                    printf "%s\n" "[
                        {\"id\":41,\"app\":\"Zoom\",\"title\":\"Zoom Workplace\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-3058,\"y\":-559,\"w\":1525,\"h\":1243}},
                        {\"id\":51,\"app\":\"Microsoft Teams\",\"title\":\"Teams Meeting\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-1529,\"y\":-559,\"w\":1525,\"h\":1243}}
                    ]"
                case meeting_bad
                    printf "%s\n" "[
                        {\"id\":41,\"app\":\"Zoom\",\"title\":\"Zoom Workplace\",\"space\":7,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-3058,\"y\":-559,\"w\":1525,\"h\":1243}},
                        {\"id\":51,\"app\":\"Microsoft Teams\",\"title\":\"Teams Meeting\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-1529,\"y\":-559,\"w\":1525,\"h\":1243}}
                    ]"
                case coding
                    printf "%s\n" "[
                        {\"id\":21,\"app\":\"Warp\",\"title\":\"Warp\",\"space\":4,\"display\":1,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":4,\"y\":44,\"w\":1792,\"h\":745}},
                        {\"id\":22,\"app\":\"SmartGit\",\"title\":\"SmartGit\",\"space\":6,\"display\":1,\"can-move\":false,\"is-minimized\":false,\"frame\":{\"x\":300,\"y\":60,\"w\":1200,\"h\":1040}}
                    ]"
            end
        end

        function get_workspace_primary_display_uuid
            echo primary
        end

        function ws_window
            set -g __work_smoke_observation_mutations (math $__work_smoke_observation_mutations + 1)
            return 1
        end

        function ws_move_windows_to_space
            set -g __work_smoke_observation_mutations (math $__work_smoke_observation_mutations + 1)
            return 1
        end

        function workspace_prepare_labeled_space
            set -g __work_smoke_observation_mutations (math $__work_smoke_observation_mutations + 1)
            return 1
        end

        function cleanup_unlabeled_empty_spaces
            set -g __work_smoke_observation_mutations (math $__work_smoke_observation_mutations + 1)
            return 1
        end

        function open
            set -g __work_smoke_observation_mutations (math $__work_smoke_observation_mutations + 1)
            return 1
        end

        set -l snapshot_json (workspace_snapshot)
        or exit 1
        echo $snapshot_json | ws_jq -e "
            .version == 1
            and (.displays | length) == 2
            and (.spaces | length) == 2
            and (.windows | length) == 2
        " >/dev/null
        or exit 2
        test "$__work_smoke_observation_display_queries" -eq 1
        and test "$__work_smoke_observation_space_queries" -eq 1
        and test "$__work_smoke_observation_window_queries" -eq 1
        or exit 3

        workspace_snapshot --caller unsafe >/dev/null 2>&1
        and exit 13

        set -l meeting_plan (workspace_plan --json gtd_meeting_wide)
        or exit 4
        echo $meeting_plan | ws_jq -e "
            .workspace == \"gtd_meeting_wide\"
            and .read_only == true
            and .status == \"ready_existing\"
            and .target_display == 2
            and .target_space == 8
            and ([.roles[] | select(.role == \"zoom\") | .selected_ids[]] == [41])
            and ([.roles[] | select(.role == \"teams\") | .selected_ids[]] == [51])
            and (first(.roles[] | select(.role == \"zoom\") | .layout.grid) == \"1:2:0:0:1:1\")
            and (first(.roles[] | select(.role == \"teams\") | .layout.grid) == \"1:2:1:0:1:1\")
        " >/dev/null
        or exit 5

        set -l meeting_verify (workspace_verify --json gtd_meeting_wide)
        or exit 6
        echo $meeting_verify | ws_jq -e ".ok == true" >/dev/null
        or exit 7

        set -g __work_smoke_observation_fixture meeting_bad
        set -l meeting_bad_verify (workspace_verify --json gtd_meeting_wide)
        set -l meeting_bad_status $status
        test "$meeting_bad_status" -ne 0
        or exit 8
        echo $meeting_bad_verify | ws_jq -e "
            .ok == false
            and (first(.checks[] | select(.name == \"owned_windows_on_target\") | .ok) == false)
        " >/dev/null
        or exit 9

        set -g __work_smoke_observation_fixture coding
        set -l coding_plan (workspace_plan --json coding_control)
        or exit 10
        echo $coding_plan | ws_jq -e "
            .workspace == \"coding_control\"
            and .target_display == 1
            and ([.roles[] | select(.role == \"warp\") | .selected_ids[]] == [21])
            and ([.roles[] | select(.role == \"smartgit\") | .fallback_candidate_ids[]] == [22])
            and (first(.roles[] | select(.role == \"warp\") | .layout.grid) == \"3:1:0:0:1:2\")
            and (first(.roles[] | select(.role == \"portfolio_performance\") | .layout) == {
                kind: \"absolute\",
                x: 420,
                y: 180,
                width: 1220,
                height: 852,
                tolerance: 8
            })
        " >/dev/null
        or exit 11

        test "$__work_smoke_observation_mutations" -eq 0
        or exit 12
    '
    fish -lc "$workspace_observability_smoke" >/tmp/work-observability-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      workspace snapshot plan verify"
    else
        echo "FAIL    workspace snapshot plan verify"
        cat /tmp/work-observability-smoke.out
        set failed 1
    end

    work_smoke_observability
    or set failed 1

    work_smoke_finalization >/tmp/work-smoke-finalization.out 2>&1
    if test $status -eq 0
        echo "OK      workspace finalization fixtures"
    else
        echo "FAIL    workspace finalization fixtures"
        cat /tmp/work-smoke-finalization.out
        set failed 1
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
                    {\"index\": 2, \"uuid\": \"external-wide\", \"frame\": {\"x\": -3062, \"y\": -594, \"w\": 3062, \"h\": 1282}},
                    {\"index\": 3, \"uuid\": \"external-tall\", \"frame\": {\"x\": 1800, \"y\": 0, \"w\": 1282, \"h\": 3062}}
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

        test (resolve_workspace_external_display tall) = 3
        or exit 2

        test (resolve_workspace_external_display) = 2
        or exit 3

        test "$__work_smoke_display_query_calls" -eq 4
        or exit 4
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

    set -l labeled_cleanup_query_failure_smoke '
        work_reload >/dev/null

        set -g __work_smoke_cleanup_query_calls 0

        function ws_yabai
            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--spaces"
                set -g __work_smoke_cleanup_query_calls (math $__work_smoke_cleanup_query_calls + 1)
                test "$WORKSPACE_YABAI_QUERY_TIMEOUT_SECONDS" = 1
                or return 2
            end

            return 1
        end

        workspace_run_cleanup_specs gtd:tall
        or exit 1

        test "$__work_smoke_cleanup_query_calls" -eq 2
        or exit 2
    '
    fish -lc "$labeled_cleanup_query_failure_smoke" >/tmp/work-labeled-cleanup-query-failure-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      labeled cleanup query failure is nonblocking"
    else
        echo "FAIL    labeled cleanup query failure is nonblocking"
        cat /tmp/work-labeled-cleanup-query-failure-smoke.out
        set failed 1
    end

    set -l cleanup_specs_shared_query_smoke '
        work_reload >/dev/null

        set -g __work_smoke_cleanup_space_query_calls 0
        set -g __work_smoke_cleanup_window_query_calls 0
        set -g __work_smoke_cleanup_destroy_calls

        function ws_yabai
            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--spaces"
                set -g __work_smoke_cleanup_space_query_calls (math $__work_smoke_cleanup_space_query_calls + 1)
                printf "%s\n" "[
                    {\"index\": 3, \"display\": 2, \"label\": \"gtd_review_tall\", \"windows\": [99]},
                    {\"index\": 4, \"display\": 2, \"label\": \"gtd_review_solo\", \"windows\": []}
                ]"
                return 0
            end

            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--windows"
                set -g __work_smoke_cleanup_window_query_calls (math $__work_smoke_cleanup_window_query_calls + 1)
                printf "%s\n" "[{\"id\":99,\"app\":\"Teams\",\"space\":3,\"is-sticky\":true}]"
                return 0
            end

            if test (count $argv) -eq 4 -a "$argv[1]" = "-m" -a "$argv[2]" = "space" -a "$argv[4]" = "--destroy"
                set -ga __work_smoke_cleanup_destroy_calls $argv[3]
                return 0
            end

            return 1
        end

        workspace_run_cleanup_specs gtd:tall gtd:solo >/dev/null
        or exit 1

        test "$__work_smoke_cleanup_space_query_calls" -eq 1
        or exit 2

        test "$__work_smoke_cleanup_window_query_calls" -eq 1
        or exit 3

        test (string join , -- $__work_smoke_cleanup_destroy_calls) = 3,4
        or exit 4
    '
    fish -lc "$cleanup_specs_shared_query_smoke" >/tmp/work-cleanup-specs-shared-query-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      cleanup specs share Space/window query"
    else
        echo "FAIL    cleanup specs share Space/window query"
        cat /tmp/work-cleanup-specs-shared-query-smoke.out
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

    set -l query_restart_recovery_smoke '
        work_reload >/dev/null

        set -g __work_smoke_query_calls 0
        set -g __work_smoke_restart_calls 0

        function sleep
        end

        function ws_restart_yabai
            set -g __work_smoke_restart_calls (math $__work_smoke_restart_calls + 1)
            return 0
        end

        function ws_yabai
            if test (count $argv) -eq 3 -a "$argv[1]" = "-m" -a "$argv[2]" = "query" -a "$argv[3]" = "--spaces"
                set -g __work_smoke_query_calls (math $__work_smoke_query_calls + 1)
                if test "$__work_smoke_query_calls" -le 2
                    return 1
                end

                printf "%s\n" "[
                    {\"index\": 8, \"display\": 2, \"label\": \"gtd_support_wide\"}
                ]"
                return 0
            end

            return 1
        end

        set -l labels (ws_query_spaces gtd_support_wide recover | ws_jq -r ".[].label")
        or exit 1

        test "$labels" = gtd_support_wide
        or exit 2

        test "$__work_smoke_restart_calls" -eq 1
        or exit 3

        test "$__work_smoke_query_calls" -eq 3
        or exit 4
    '
    fish -lc "$query_restart_recovery_smoke" >/tmp/work-query-restart-recovery-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      query yabai restart recovery"
    else
        echo "FAIL    query yabai restart recovery"
        cat /tmp/work-query-restart-recovery-smoke.out
        set failed 1
    end

    set -l legacy_yabai_service_restart_smoke '
        work_reload >/dev/null

        set -g __work_smoke_launchctl_calls

        function launchctl
            set -ga __work_smoke_launchctl_calls (string join " " -- $argv)

            if test "$argv[1]" = print
                return 0
            end

            if test "$argv[1]" = kickstart
                return 0
            end

            return 1
        end

        function ws_yabai
            return 1
        end

        ws_restart_yabai work_smoke
        or exit 1

        set -l service "gui/"(id -u)"/com.asmvik.yabai"
        contains -- "print $service" $__work_smoke_launchctl_calls
        or exit 2

        contains -- "kickstart -k $service" $__work_smoke_launchctl_calls
        or exit 3
    '
    fish -lc "$legacy_yabai_service_restart_smoke" >/tmp/work-legacy-yabai-service-restart-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      legacy yabai LaunchAgent restart"
    else
        echo "FAIL    legacy yabai LaunchAgent restart"
        cat /tmp/work-legacy-yabai-service-restart-smoke.out
        set failed 1
    end

    set -l readonly_query_no_restart_smoke '
        work_reload >/dev/null

        set -g __work_smoke_restart_calls 0

        function sleep
        end

        function ws_restart_yabai
            set -g __work_smoke_restart_calls (math $__work_smoke_restart_calls + 1)
            return 0
        end

        function ws_yabai
            return 1
        end

        if ws_query_spaces work_smoke recover >/dev/null 2>&1
            exit 1
        end

        test "$__work_smoke_restart_calls" -eq 0
        or exit 2

        if ws_query_spaces yabai_doctor read-only >/dev/null 2>&1
            exit 3
        end

        test "$__work_smoke_restart_calls" -eq 0
        or exit 4
    '
    fish -lc "$readonly_query_no_restart_smoke" >/tmp/work-readonly-query-no-restart-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      read-only query does not restart yabai"
    else
        echo "FAIL    read-only query does not restart yabai"
        cat /tmp/work-readonly-query-no-restart-smoke.out
        set failed 1
    end

    set -l app_unmovable_restart_smoke '
        work_reload >/dev/null

        set -g __work_smoke_restart_calls 0
        set -g __work_smoke_query_phases
        set -g __work_smoke_allow_movable 0

        function sleep
        end

        function perl
            return 0
        end

        function ws_focus_space
        end

        function ws_restart_yabai
            set -g __work_smoke_restart_calls (math $__work_smoke_restart_calls + 1)
            return 0
        end

        function workspace_select_app_window
            argparse "app=" "space=" movable visible -- $argv
            or return 1

            if set -q _flag_movable
                if test "$__work_smoke_allow_movable" = 1
                    echo 44
                end
            else
                echo 44
            end
        end

        function ws_query_windows
            set -l phase $argv[2]
            set -ga __work_smoke_query_phases $phase

            if test "$phase" = find_Preview_after_yabai_restart
                set -g __work_smoke_allow_movable 1
                printf "%s\n" "[{\"id\":44,\"app\":\"Preview\",\"space\":6,\"can-move\":true,\"is-minimized\":false}]"
                return 0
            end

            set -g __work_smoke_allow_movable 0
            printf "%s\n" "[{\"id\":44,\"app\":\"Preview\",\"space\":6,\"can-move\":false,\"is-minimized\":false}]"
            return 0
        end

        set -l window_id (workspace_find_app_window --app Preview --caller gtd_review_wide --attempts 1 --wait 0 2>/dev/null)
        or exit 1

        test "$window_id" = 44
        or exit 2

        test "$__work_smoke_restart_calls" -eq 1
        or exit 3

        contains -- find_Preview_after_yabai_restart $__work_smoke_query_phases
        or exit 4
    '
    fish -lc "$app_unmovable_restart_smoke" >/tmp/work-app-unmovable-restart-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      app unmovable yabai restart recovery"
    else
        echo "FAIL    app unmovable yabai restart recovery"
        cat /tmp/work-app-unmovable-restart-smoke.out
        set failed 1
    end

    set -l capture_confirm_restart_smoke '
        work_reload >/dev/null

        set -g __work_smoke_restart_calls 0
        set -g __work_smoke_moved ""
        set -g __work_smoke_target_available 0

        function sleep
        end

        function ws_restart_yabai
            set -g __work_smoke_restart_calls (math $__work_smoke_restart_calls + 1)
            set -g __work_smoke_target_available 1
            return 0
        end

        function ws_move_windows_to_space
            set -g __work_smoke_moved (string join , -- $argv)
        end

        function workspace_find_app_window
            argparse "app=" "caller=" "space=" no-refresh target-only visible -- $argv
            or return 1

            if not set -q _flag_space
                echo 44
                return 0
            end

            if set -q _flag_target_only
                if test "$__work_smoke_target_available" = 1
                    echo 44
                end
                return 0
            end

            return 0
        end

        set -l window_id (workspace_capture_app_window --app Preview --caller gtd_review_wide --space 8)
        or exit 1

        test "$window_id" = 44
        or exit 2

        test "$__work_smoke_moved" = "8,44"
        or exit 3

        test "$__work_smoke_restart_calls" -eq 1
        or exit 4
    '
    fish -lc "$capture_confirm_restart_smoke" >/tmp/work-capture-confirm-restart-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      capture confirmation yabai restart recovery"
    else
        echo "FAIL    capture confirmation yabai restart recovery"
        cat /tmp/work-capture-confirm-restart-smoke.out
        set failed 1
    end

    set -l focus_already_focused_smoke '
        work_reload >/dev/null

        set -g __work_smoke_focus_calls

        function ws_yabai
            if test (count $argv) -eq 4 -a "$argv[1]" = "-m" -a "$argv[2]" = "display" -a "$argv[3]" = "--focus"
                set -ga __work_smoke_focus_calls display
                echo "cannot focus an already focused display." >&2
                return 1
            end

            if test (count $argv) -eq 4 -a "$argv[1]" = "-m" -a "$argv[2]" = "space" -a "$argv[3]" = "--focus"
                set -ga __work_smoke_focus_calls space
                echo "cannot focus an already focused space." >&2
                return 1
            end

            return 1
        end

        ws_focus_display 2
        or exit 1

        ws_focus_space 7
        or exit 2

        test (string join , $__work_smoke_focus_calls) = "display,space"
        or exit 3
    '
    fish -lc "$focus_already_focused_smoke" >/tmp/work-focus-already-focused-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      focus already-focused fallback"
    else
        echo "FAIL    focus already-focused fallback"
        cat /tmp/work-focus-already-focused-smoke.out
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

    set -l aggregate_space_order_smoke '
        work_reload >/dev/null
        set -e WORKSPACE_SKIP_FINALIZATION
        if set -q WORKSPACE_TEST_SOURCE_ROOT
            source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_finalize.fish"
            source "$WORKSPACE_TEST_SOURCE_ROOT/common/work_entries.fish"
        end

        set -g __work_smoke_aggregate_calls
        set -g __work_smoke_fail_wide 1

        for command_name in \
                coding_solo research_solo gtd_solo_all \
                research_wide office_wide gtd_ai_wide gtd_support_wide gtd_review_wide coding_editor_wide \
                gtd_mail_wide gtd_meeting_wide \
                research_tall office_tall gtd_ai_tall gtd_support_tall gtd_review_tall coding_editor_tall \
                gtd_mail_tall gtd_meeting_tall \
                gtd_ai_expand_hermes_when_alone gtd_chat gtd_calendar coding_control workspace_reconcile_primary_fixed_spaces
            eval "function $command_name; set -ga __work_smoke_aggregate_calls $command_name; if test \"$command_name\" = research_wide -a \"\$__work_smoke_fail_wide\" = 1; return 1; end; end"
        end

        function workspace_run_step
            set -e argv[1]
            $argv
        end

        function workspace_finalize_mode
            set -ga __work_smoke_aggregate_calls finalize:$argv[1]
        end

        work_wide
        set -l wide_status $status
        test "$wide_status" -ne 0
        or exit 1
        test "$__work_smoke_aggregate_calls[-1]" = finalize:wide
        or exit 2

        set -g __work_smoke_aggregate_calls
        set -g __work_smoke_fail_wide 0
        work_tall
        or exit 3
        test "$__work_smoke_aggregate_calls[-1]" = finalize:tall
        or exit 4

        set -g __work_smoke_aggregate_calls
        work_solo
        or exit 5
        test "$__work_smoke_aggregate_calls[-1]" = finalize:solo
        or exit 6
    '
    fish -lc "$aggregate_space_order_smoke" >/tmp/work-aggregate-space-order-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      aggregate commands finish with shared finalization"
    else
        echo "FAIL    aggregate commands finish with shared finalization"
        cat /tmp/work-aggregate-space-order-smoke.out
        set failed 1
    end

    set -l space_order_health_smoke '
        work_reload >/dev/null

        function defaults
            echo 0
        end

        string match -q "*status=ok*" -- (workspace_space_order_health)
        or exit 1

        function defaults
            echo 1
        end

        string match -q "*status=warning*" -- (workspace_space_order_health)
        or exit 2
    '
    fish -lc "$space_order_health_smoke" >/tmp/work-space-order-health-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      Space ordering recent-use diagnostic"
    else
        echo "FAIL    Space ordering recent-use diagnostic"
        cat /tmp/work-space-order-health-smoke.out
        set failed 1
    end

    set -l workspace_order_spaces_smoke '
        work_reload >/dev/null
        if set -q WORKSPACE_TEST_SOURCE_ROOT
            source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_order_spaces.fish"
        end

        set -g __work_smoke_order_query_calls 0
        set -g __work_smoke_order_commands
        set -g __work_smoke_order_spaces "[
            {\"index\":1,\"display\":1,\"label\":\"coding_control\",\"uuid\":\"control\"},
            {\"index\":2,\"display\":1,\"label\":\"gtd_chat\",\"uuid\":\"chat\"},
            {\"index\":3,\"display\":1,\"label\":\"gtd_calendar\",\"uuid\":\"calendar\"},
            {\"index\":4,\"display\":1,\"label\":\"\",\"uuid\":\"home\"},
            {\"index\":5,\"display\":1,\"label\":\"\",\"uuid\":\"spare\"},
            {\"index\":6,\"display\":2,\"label\":\"coding_editor_wide\",\"uuid\":\"editor\"},
            {\"index\":7,\"display\":2,\"label\":\"research_wide\",\"uuid\":\"research\"},
            {\"index\":8,\"display\":2,\"label\":\"gtd_mail_wide\",\"uuid\":\"mail\"},
            {\"index\":9,\"display\":2,\"label\":\"gtd_ai\",\"uuid\":\"ai\"},
            {\"index\":10,\"display\":2,\"label\":\"gtd_meeting_wide\",\"uuid\":\"meeting\"}
        ]"

        function resolve_workspace_primary_display
            echo 1
        end

        function workspace_resolve_display_role
            echo 2
        end

        function ws_query_spaces
            set -g __work_smoke_order_query_calls (math $__work_smoke_order_query_calls + 1)
            echo $__work_smoke_order_spaces
        end

        function ws_yabai
            set -ga __work_smoke_order_commands (string join " " -- $argv)

            test (count $argv) -eq 5
            and test "$argv[1]" = -m
            and test "$argv[2]" = space
            and test "$argv[4]" = --move
            or return 1

            set -l selector $argv[3]
            set -l target $argv[5]
            set -g __work_smoke_order_spaces (echo $__work_smoke_order_spaces | ws_jq -c \
                --arg selector "$selector" \
                --argjson target "$target" "
                    (first(.[] | select(.label == \$selector or (.index | tostring) == \$selector)).display) as \$display
                    | ([.[] | select(.display == \$display)] | sort_by(.index)) as \$display_spaces
                    | (\$display_spaces | map(.index) | min) as \$first_index
                    | (first(\$display_spaces[] | select(.label == \$selector or (.index | tostring) == \$selector))) as \$selected
                    | (\$display_spaces | map(select(.uuid != \$selected.uuid))) as \$remaining
                    | (\$target - \$first_index) as \$offset
                    | (\$remaining[0:\$offset] + [\$selected] + \$remaining[\$offset:]) as \$ordered
                    | (\$ordered | to_entries | map(.value + {index: (\$first_index + .key)})) as \$updated
                    | ([.[] | select(.display != \$display)] + \$updated | sort_by(.index))
                ")
        end

        workspace_order_mode_spaces wide
        or exit 1

        test (echo $__work_smoke_order_spaces | ws_jq -r \
            "first(.[] | select(.display == 1) | .uuid)") = home
        or exit 2

        test "$__work_smoke_order_commands[1]" = "-m space 4 --move 1"
        or exit 3

        test (echo $__work_smoke_order_spaces | ws_jq -r \
            "[.[] | select(.display == 1) | .label] | join(\",\")") = ",gtd_chat,gtd_calendar,coding_control,"
        or exit 4

        test (echo $__work_smoke_order_spaces | ws_jq -r \
            "[.[] | select(.display == 2) | .label] | join(\",\")") = \
            "research_wide,gtd_ai,coding_editor_wide,gtd_mail_wide,gtd_meeting_wide"
        or exit 5

        test "$__work_smoke_order_query_calls" -gt (count $__work_smoke_order_commands)
        or exit 6

        for command_line in $__work_smoke_order_commands
            string match -rq -- "--create|--destroy|--display" "$command_line"
            and exit 7
        end

        set -g __work_smoke_order_spaces "[
            {\"index\":1,\"display\":1,\"label\":\"\",\"uuid\":\"home\"},
            {\"index\":2,\"display\":1,\"label\":\"gtd_chat\",\"uuid\":\"chat\"},
            {\"index\":3,\"display\":1,\"label\":\"coding_control\",\"uuid\":\"control\"},
            {\"index\":4,\"display\":1,\"label\":\"gtd_calendar\",\"uuid\":\"calendar\"},
            {\"index\":5,\"display\":2,\"label\":\"research_wide\",\"uuid\":\"research\"}
        ]"
        set -g __work_smoke_order_commands

        workspace_order_mode_spaces wide
        or exit 8

        for command_line in $__work_smoke_order_commands
            string match -q -- "-m space 1 --move *" "$command_line"
            and exit 9
        end

        set -g __work_smoke_order_spaces "[
            {\"index\":1,\"display\":1,\"label\":\"gtd_calendar\",\"uuid\":\"calendar\"},
            {\"index\":2,\"display\":1,\"label\":\"gtd_chat\",\"uuid\":\"chat\"},
            {\"index\":3,\"display\":1,\"label\":\"coding_control\",\"uuid\":\"control\"},
            {\"index\":4,\"display\":2,\"label\":\"research_wide\",\"uuid\":\"research\"}
        ]"

        workspace_order_mode_spaces wide
        or exit 10

        test (echo $__work_smoke_order_spaces | ws_jq -r \
            "[.[] | select(.display == 1) | .label] | join(\",\")") = \
            "gtd_chat,gtd_calendar,coding_control"
        or exit 11

        exit 0
    '
    fish -lc "$workspace_order_spaces_smoke" >/tmp/work-order-spaces-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      label-based primary and external Space ordering"
    else
        echo "FAIL    label-based primary and external Space ordering"
        cat /tmp/work-order-spaces-smoke.out
        set failed 1
    end

    set -l workspace_order_all_modes_home_selector_smoke '
        work_reload >/dev/null
        if set -q WORKSPACE_TEST_SOURCE_ROOT
            source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_order_spaces.fish"
        end

        set -g __work_smoke_home_selectors

        function resolve_workspace_primary_display
            echo 1
        end

        function workspace_resolve_display_role
            echo 2
        end

        function ws_query_spaces
            echo "[
                {\"index\":1,\"display\":1,\"label\":\"coding_control\",\"uuid\":\"CONTROL\"},
                {\"index\":2,\"display\":1,\"label\":\"gtd_chat\",\"uuid\":\"CHAT\"},
                {\"index\":3,\"display\":1,\"label\":\"gtd_calendar\",\"uuid\":\"CALENDAR\"},
                {\"index\":4,\"display\":1,\"label\":\"\",\"uuid\":\"HOME-UUID\"}
            ]"
        end

        function ws_yabai
            set -ga __work_smoke_home_selectors $argv[3]
        end

        function __workspace_wait_for_space_index
            return 0
        end

        for mode in solo wide tall
            set -g __work_smoke_home_selectors
            workspace_order_mode_spaces $mode
            or exit 1
            test "$__work_smoke_home_selectors[1]" = 4
            or exit 2
            not contains -- HOME-UUID $__work_smoke_home_selectors
            or exit 3
        end
    '
    fish -lc "$workspace_order_all_modes_home_selector_smoke" >/tmp/work-order-all-modes-home-selector-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      solo/wide/tall Home ordering uses live index"
    else
        echo "FAIL    solo/wide/tall Home ordering uses live index"
        cat /tmp/work-order-all-modes-home-selector-smoke.out
        set failed 1
    end

    set -l workspace_order_home_failure_smoke '
        work_reload >/dev/null
        if set -q WORKSPACE_TEST_SOURCE_ROOT
            source "$WORKSPACE_TEST_SOURCE_ROOT/common/workspace_order_spaces.fish"
        end

        function resolve_workspace_primary_display
            echo 1
        end

        function workspace_resolve_display_role
            echo 2
        end

        function ws_query_spaces
            printf "%s\n" "[
                {\"index\":1,\"display\":1,\"label\":\"coding_control\",\"uuid\":\"control\"},
                {\"index\":2,\"display\":1,\"label\":\"\",\"uuid\":\"home\"},
                {\"index\":3,\"display\":2,\"label\":\"research_wide\",\"uuid\":\"research\"}
            ]"
        end

        function ws_yabai
            if test "$argv[3]" = 2
                return 1
            end
        end

        workspace_order_mode_spaces wide
        test $status -ne 0
        or exit 1
    '
    fish -lc "$workspace_order_home_failure_smoke" >/tmp/work-order-home-failure-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      Home Space ordering failure propagation"
    else
        echo "FAIL    Home Space ordering failure propagation"
        cat /tmp/work-order-home-failure-smoke.out
        set failed 1
    end

    set -l ownership_policy_rows (workspace_ownership_policy_rows)

    set -l required_ownership_patterns \
        "*gtd_support_*Dia*all-movable-windows*" \
        "*gtd_review_*Finder*all-movable-windows*" \
        "*gtd_review_*Preview*all-movable-windows;fallback-space-owner*" \
        "*gtd_review_*Notes*all-movable-windows;fallback-space-owner*" \
        "*gtd_meeting_*Zoom*all-movable-windows;fallback-space-owner*" \
        "*gtd_meeting_*Microsoft Teams/MSTeams*all-movable-windows;fallback-space-owner*" \
        "*gtd_mail_*Thunderbird*single-window;fallback-space-owner*" \
        "*gtd_mail_*Microsoft Outlook*optional-helper*" \
        "*gtd_ai*Hermes*single-window*" \
        "*gtd_ai*ChatGPT*single-window*" \
        "*gtd_ai*Obsidian*single-window*" \
        "*gtd_calendar*Calendar*single-window;fallback-space-owner*" \
        "*coding_editor_*Code*single-window*" \
        "*coding_editor_wide/tall*ChatGPT*optional-helper*" \
        "*coding_control*SmartGit*single-window;fallback-space-owner*" \
        "*coding_control*Portfolio Performance*single-window*" \
        "*research_*Claude*optional-helper*" \
        "*office_writing_*Microsoft Word*all-movable-windows*" \
        "*office_slides_*Microsoft PowerPoint*all-movable-windows*"

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
            and string match -q "*OK      mode symmetry: solo/wide/tall aggregate commands*" -- "$audit_output"
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

    set -l review_notes_reconcile_smoke '
        work_reload >/dev/null

        set -g __work_smoke_review_move_calls
        set -g __work_smoke_review_grid_calls

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            set -l phase $argv[2]

            if test "$phase" = initial
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 15, \"app\": \"Notes\", \"space\": 9, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 12, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            else if test "$phase" = final_review_reconcile
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 15, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 12, \"app\": \"Preview\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"}
                ]"
            else
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 15, \"app\": \"Notes\", \"space\": 9, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 12, \"app\": \"Preview\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
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

        function ws_move_windows_to_space
            set -ga __work_smoke_review_move_calls (string join , -- $argv)
        end

        function ws_window
            set -ga __work_smoke_review_grid_calls (string join , -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_review_space --label gtd_review_wide --display wide --finder-grid 1:1:0:0:1:1 --preview-grid 1:1:0:0:1:1 --notes-grid 1:1:0:0:1:1
        or exit 1

        test "$__work_smoke_review_move_calls[1]" = "8,14,12,11,15"
        or exit 2

        test "$__work_smoke_review_move_calls[2]" = "8,15"
        or exit 3

        contains -- "11,--grid,1:1:0:0:1:1" $__work_smoke_review_grid_calls
        or exit 4

        contains -- "15,--grid,1:1:0:0:1:1" $__work_smoke_review_grid_calls
        or exit 5
    '
    fish -lc "$review_notes_reconcile_smoke" >/tmp/work-review-notes-reconcile-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      review movable Notes reconcile"
    else
        echo "FAIL    review movable Notes reconcile"
        cat /tmp/work-review-notes-reconcile-smoke.out
        set failed 1
    end

    set -l review_noop_move_filter_smoke '
        work_reload >/dev/null

        set -g __work_smoke_review_move_calls
        set -g __work_smoke_review_focus_args

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                {\"id\": 12, \"app\": \"Preview\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                {\"id\": 14, \"app\": \"Finder\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"},
                {\"id\": 17, \"app\": \"ChatGPT\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"ChatGPT\"}
            ]"
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
            set -g __work_smoke_review_focus_args (string join , -- $argv)
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

        gtd_apply_review_space --label gtd_review_wide --display wide --finder-grid 1:1:0:0:1:1 --preview-grid 1:1:0:0:1:1 --chatgpt-grid 1:1:0:0:1:1 --notes-grid 1:1:0:0:1:1 gtd:tall gtd:solo
        or exit 1

        test (count $__work_smoke_review_move_calls) -eq 0
        or exit 2

        test "$__work_smoke_review_focus_args" = "gtd_review_wide,8,2,float"
        or exit 3
    '
    fish -lc "$review_noop_move_filter_smoke" >/tmp/work-review-noop-move-filter-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      review no-op move filtering"
    else
        echo "FAIL    review no-op move filtering"
        cat /tmp/work-review-noop-move-filter-smoke.out
        set failed 1
    end

    set -l review_obsidian_smoke '
        work_reload >/dev/null
        if set -q WORKSPACE_TEST_SOURCE_ROOT
            source "$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_apply_review_space.fish"
        end

        set -g __work_smoke_obsidian_space 4
        set -g __work_smoke_obsidian_present 1
        set -g __work_smoke_obsidian_movable true
        set -g __work_smoke_review_move_calls
        set -g __work_smoke_review_grid_calls
        set -g __work_smoke_review_find_calls
        set -g __work_smoke_review_destroy_calls
        set -g __work_smoke_review_retarget_args

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            if test "$__work_smoke_obsidian_present" -eq 1
                printf "[{\"id\":121,\"app\":\"Obsidian\",\"space\":%s,\"display\":2,\"can-move\":%s,\"is-minimized\":false,\"title\":\"Obsidian\"}]\n" \
                    $__work_smoke_obsidian_space $__work_smoke_obsidian_movable
            else
                printf "[]\n"
            end
        end

        function workspace_find_app_key_window
            set -ga __work_smoke_review_find_calls (string join , -- $argv)
        end

        function workspace_resolve_display_role
            echo 2
        end

        function find_or_create_labeled_space
            echo 8
        end

        function workspace_retarget_contaminated_space
            set -g __work_smoke_review_retarget_args (string join " " -- $argv)
            echo 8
        end

        function workspace_focus_labeled_space
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_review_move_calls (string join , -- $argv)
            if contains -- 121 $argv
                set -g __work_smoke_obsidian_space $argv[1]
            end
        end

        function ws_window
            set -ga __work_smoke_review_grid_calls (string join , -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        function destroy_empty_labeled_space
            set -ga __work_smoke_review_destroy_calls (string join , -- $argv)
        end

        gtd_apply_review_space \
            --label gtd_review_wide \
            --display wide \
            --obsidian-grid 2:16:10:0:6:1
        or exit 1

        test "$__work_smoke_review_move_calls[1]" = "8,121"
        or exit 2

        contains -- "121,--grid,2:16:10:0:6:1" $__work_smoke_review_grid_calls
        or exit 3

        test (count $__work_smoke_review_destroy_calls) -eq 0
        or exit 4

        string match -q "*Obsidian*" -- "$__work_smoke_review_retarget_args"
        or exit 5

        for find_call in $__work_smoke_review_find_calls
            string match -q "*obsidian*" -- "$find_call"
            and exit 6
        end

        set -g __work_smoke_obsidian_space 8
        set -g __work_smoke_review_move_calls
        set -g __work_smoke_review_grid_calls

        gtd_apply_review_space \
            --label gtd_review_wide \
            --display wide \
            --obsidian-grid 2:16:10:0:6:1
        or exit 7

        test (count $__work_smoke_review_move_calls) -eq 0
        or exit 8

        contains -- "121,--grid,2:16:10:0:6:1" $__work_smoke_review_grid_calls
        or exit 9

        set -g __work_smoke_obsidian_present 0
        set -g __work_smoke_review_find_calls

        gtd_apply_review_space \
            --label gtd_review_wide \
            --display wide \
            --obsidian-grid 2:16:10:0:6:1
        or exit 10

        for find_call in $__work_smoke_review_find_calls
            string match -q "*obsidian*" -- "$find_call"
            and exit 11
        end

        exit 0
    '
    fish -lc "$review_obsidian_smoke" >/tmp/work-review-obsidian-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      review Obsidian ownership and layout"
    else
        echo "FAIL    review Obsidian ownership and layout"
        cat /tmp/work-review-obsidian-smoke.out
        set failed 1
    end

    set -l review_obsidian_unmovable_smoke '
        work_reload >/dev/null
        if set -q WORKSPACE_TEST_SOURCE_ROOT
            source "$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_apply_review_space.fish"
        end

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            printf "%s\n" "[{
                \"id\":121,
                \"app\":\"Obsidian\",
                \"space\":4,
                \"display\":2,
                \"can-move\":false,
                \"is-minimized\":false,
                \"title\":\"Obsidian\"
            }]"
        end

        function workspace_find_app_key_window
        end

        function destroy_empty_labeled_space
        end

        gtd_apply_review_space \
            --label gtd_review_wide \
            --display wide \
            --obsidian-grid 2:16:10:0:6:1 \
            2>/tmp/work-review-obsidian-warning.out
        test $status -ne 0
        or exit 1

        string match -q "*found Obsidian, but no movable window was available*" -- (cat /tmp/work-review-obsidian-warning.out)
        or exit 2
    '
    fish -lc "$review_obsidian_unmovable_smoke" >/tmp/work-review-obsidian-unmovable-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      review unmovable Obsidian failure"
    else
        echo "FAIL    review unmovable Obsidian failure"
        cat /tmp/work-review-obsidian-unmovable-smoke.out
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
        if set -q WORKSPACE_TEST_SOURCE_ROOT
            source "$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_apply_review_space.fish"
        end

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
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"},
                    {\"id\": 121, \"app\": \"Obsidian\", \"space\": 7, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Obsidian\"}
                ]"
            else if test "$phase" = preview_move_fallback
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 16, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 17, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"},
                    {\"id\": 121, \"app\": \"Obsidian\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Obsidian\"}
                ]"
            else if test "$phase" = preview_move_fallback_before_move
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 16, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 17, \"app\": \"Preview\", \"space\": 9, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"},
                    {\"id\": 121, \"app\": \"Obsidian\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Obsidian\"}
                ]"
            else
                printf "%s\n" "[
                    {\"id\": 11, \"app\": \"Notes\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Notes\"},
                    {\"id\": 16, \"app\": \"Preview\", \"space\": 6, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 17, \"app\": \"Preview\", \"space\": 9, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Preview\"},
                    {\"id\": 14, \"app\": \"Finder\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Finder\"},
                    {\"id\": 121, \"app\": \"Obsidian\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Obsidian\"}
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

        gtd_apply_review_space --label gtd_review_wide --display wide --finder-grid 1:1:0:0:1:1 --preview-grid 1:1:0:0:1:1 --notes-grid 1:1:0:0:1:1 --obsidian-grid 1:1:0:0:1:1
        or exit 1

        test "$__work_smoke_review_move_calls[1]" = "8,14,12,121,11"
        or exit 2

        contains -- "8,16,17" $__work_smoke_review_move_calls
        or exit 3

        contains -- "6,14,16,17,11,121" $__work_smoke_review_move_calls
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

    if set -q WORKSPACE_TEST_SOURCE_ROOT
        source "$WORKSPACE_TEST_SOURCE_ROOT/gtd/internal/gtd_support_find_dia_windows.fish"
    end

    set -l dia_accessibility_fixture '[
        {"id": 31, "app": "Dia", "title": "GTD", "role": "AXWindow", "subrole": "AXStandardWindow", "space": 8, "can-move": true, "is-minimized": false, "is-native-fullscreen": false},
        {"id": 32, "app": "Dia", "title": "Research", "role": "AXWindow", "subrole": "AXStandardWindow", "space": 3, "can-move": true, "is-minimized": false, "is-native-fullscreen": false},
        {"id": 33, "app": "Dia", "title": "", "role": "AXHelpTag", "subrole": "", "space": 8, "can-move": true, "is-minimized": false, "is-native-fullscreen": false}
    ]'
    set -l dia_browser_windows (printf '%s\n' "$dia_accessibility_fixture" | gtd_support_find_dia_windows gtd_support_wide)
    if test $status -eq 0 -a (string join , $dia_browser_windows) = "31,32"
        echo "OK      Dia accessibility-helper exclusion"
    else
        echo "FAIL    Dia accessibility-helper exclusion"
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

    set -l support_partial_dia_restart_smoke '
        work_reload >/dev/null

        set -g __work_smoke_dia_refreshed 0
        set -g __work_smoke_dia_restarted 0

        function sleep
        end

        function __gtd_support_refresh_dia_app
            set -g __work_smoke_dia_refreshed 1
        end

        function ws_restart_yabai
            set -g __work_smoke_dia_restarted (math $__work_smoke_dia_restarted + 1)
            return 0
        end

        function ws_query_windows
            set -l phase $argv[2]

            if test "$phase" = dia_refresh
                printf "%s\n" "[
                    {\"id\": 31, \"app\": \"Dia\", \"space\": 8, \"can-move\": true, \"is-minimized\": false, \"is-native-fullscreen\": false},
                    {\"id\": 32, \"app\": \"Dia\", \"space\": 3, \"can-move\": false, \"is-minimized\": false, \"is-native-fullscreen\": false}
                ]"
                return 0
            end

            if test "$phase" = dia_yabai_restart
                printf "%s\n" "[
                    {\"id\": 31, \"app\": \"Dia\", \"space\": 8, \"can-move\": true, \"is-minimized\": false, \"is-native-fullscreen\": false},
                    {\"id\": 32, \"app\": \"Dia\", \"space\": 3, \"can-move\": true, \"is-minimized\": false, \"is-native-fullscreen\": false}
                ]"
                return 0
            end

            return 1
        end

        set -l dia_initial_fixture "[
            {\"id\": 31, \"app\": \"Dia\", \"space\": 8, \"can-move\": true, \"is-minimized\": false, \"is-native-fullscreen\": false},
            {\"id\": 32, \"app\": \"Dia\", \"space\": 3, \"can-move\": false, \"is-minimized\": false, \"is-native-fullscreen\": false}
        ]"
        set -l dia_windows (printf "%s\n" "$dia_initial_fixture" | gtd_support_find_dia_windows gtd_support_wide 2>/dev/null)
        or exit 1

        test (string join , $dia_windows) = "31,32"
        or exit 2

        test "$__work_smoke_dia_refreshed" = 1
        or exit 3

        test "$__work_smoke_dia_restarted" = 1
        or exit 4
    '
    fish -lc "$support_partial_dia_restart_smoke" >/tmp/work-support-partial-dia-restart-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      support partial Dia yabai restart recovery"
    else
        echo "FAIL    support partial Dia yabai restart recovery"
        cat /tmp/work-support-partial-dia-restart-smoke.out
        set failed 1
    end

    set -l support_dia_restart_smoke '
        work_reload >/dev/null

        set -g __work_smoke_dia_refreshed 0
        set -g __work_smoke_dia_restarted 0
        set -g __work_smoke_dia_query_phases

        function sleep
        end

        function __gtd_support_refresh_dia_app
            set -g __work_smoke_dia_refreshed 1
        end

        function ws_restart_yabai
            set -g __work_smoke_dia_restarted (math $__work_smoke_dia_restarted + 1)
            return 0
        end

        function ws_query_windows
            set -l phase $argv[2]
            set -ga __work_smoke_dia_query_phases $phase

            if test "$phase" = dia_refresh
                printf "%s\n" "[
                    {\"id\": 31, \"app\": \"Dia\", \"space\": 8, \"can-move\": false, \"is-minimized\": false, \"is-native-fullscreen\": false}
                ]"
                return 0
            end

            if test "$phase" = dia_yabai_restart
                printf "%s\n" "[
                    {\"id\": 31, \"app\": \"Dia\", \"space\": 8, \"can-move\": true, \"is-minimized\": false, \"is-native-fullscreen\": false}
                ]"
                return 0
            end

            return 1
        end

        set -l dia_initial_fixture "[
            {\"id\": 31, \"app\": \"Dia\", \"space\": 8, \"can-move\": false, \"is-minimized\": false, \"is-native-fullscreen\": false}
        ]"
        set -l dia_windows (printf "%s\n" "$dia_initial_fixture" | gtd_support_find_dia_windows gtd_support_wide 2>/dev/null)
        or exit 1

        test "$dia_windows" = 31
        or exit 2

        test "$__work_smoke_dia_refreshed" = 1
        or exit 3

        test "$__work_smoke_dia_restarted" = 1
        or exit 4

        contains -- dia_refresh $__work_smoke_dia_query_phases
        or exit 5

        contains -- dia_yabai_restart $__work_smoke_dia_query_phases
        or exit 6
    '
    fish -lc "$support_dia_restart_smoke" >/tmp/work-support-dia-restart-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      support Dia yabai restart recovery"
    else
        echo "FAIL    support Dia yabai restart recovery"
        cat /tmp/work-support-dia-restart-smoke.out
        set failed 1
    end

    set -l office_slides_tall_multi_window_smoke '
        work_reload >/dev/null

        set -g __work_smoke_office_capture_args ""
        set -g __work_smoke_office_moves
        set -g __work_smoke_office_grids

        function workspace_run_cleanup_specs
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

        function workspace_prepare_labeled_space
            echo 8
        end

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 17, \"app\": \"ChatGPT\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"ChatGPT\"},
                {\"id\": 21, \"app\": \"Microsoft PowerPoint\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"slides A\"},
                {\"id\": 22, \"app\": \"Microsoft PowerPoint\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"slides B\"},
                {\"id\": 23, \"app\": \"Microsoft PowerPoint\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"slides C\"}
            ]"
        end

        function workspace_capture_app_window
            set -g __work_smoke_office_capture_args (string join " " -- $argv)
            echo 17
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_office_moves (string join , -- $argv)
        end

        function ws_window
            set -ga __work_smoke_office_grids (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        office_slides_tall
        or exit 1

        string match -q "*--app-key chatgpt*" -- "$__work_smoke_office_capture_args"
        or exit 2

        contains -- "8,21,22,23" $__work_smoke_office_moves
        or exit 3

        contains -- "17 --grid 2:2:0:0:1:1" $__work_smoke_office_grids
        or exit 4

        contains -- "21 --grid 2:2:1:0:1:1" $__work_smoke_office_grids
        or exit 5

        contains -- "22 --grid 2:2:0:1:1:1" $__work_smoke_office_grids
        or exit 6

        contains -- "23 --grid 2:2:1:1:1:1" $__work_smoke_office_grids
        or exit 7
    '
    fish -lc "$office_slides_tall_multi_window_smoke" >/tmp/work-office-slides-tall-multi-window-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      office slides tall multi-window layout"
    else
        echo "FAIL    office slides tall multi-window layout"
        cat /tmp/work-office-slides-tall-multi-window-smoke.out
        set failed 1
    end

    set -l office_writing_wide_multi_window_smoke '
        work_reload >/dev/null

        set -g __work_smoke_office_capture_args ""
        set -g __work_smoke_office_moves
        set -g __work_smoke_office_grids

        function workspace_run_cleanup_specs
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

        function workspace_prepare_labeled_space
            echo 8
        end

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 17, \"app\": \"ChatGPT\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"ChatGPT\"},
                {\"id\": 31, \"app\": \"Microsoft Word\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"draft A\"},
                {\"id\": 32, \"app\": \"Microsoft Word\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"draft B\"}
            ]"
        end

        function workspace_capture_app_window
            set -g __work_smoke_office_capture_args (string join " " -- $argv)
            echo 17
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_office_moves (string join , -- $argv)
        end

        function ws_window
            set -ga __work_smoke_office_grids (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        office_writing_wide
        or exit 1

        string match -q "*--app-key chatgpt*" -- "$__work_smoke_office_capture_args"
        or exit 2

        contains -- "8,31,32" $__work_smoke_office_moves
        or exit 3

        contains -- "17 --grid 1:3:0:0:1:1" $__work_smoke_office_grids
        or exit 4

        contains -- "31 --grid 1:3:1:0:1:1" $__work_smoke_office_grids
        or exit 5

        contains -- "32 --grid 1:3:2:0:1:1" $__work_smoke_office_grids
        or exit 6
    '
    fish -lc "$office_writing_wide_multi_window_smoke" >/tmp/work-office-writing-wide-multi-window-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      office writing wide multi-window layout"
    else
        echo "FAIL    office writing wide multi-window layout"
        cat /tmp/work-office-writing-wide-multi-window-smoke.out
        set failed 1
    end

    set -l coding_control_portfolio_smoke '
        work_reload >/dev/null

        set -g __work_smoke_control_moves
        set -g __work_smoke_control_bounds
        set -g __work_smoke_portfolio_opened 0

        function perl
            if contains -- open $argv; and contains -- "Portfolio Performance" $argv
                set -g __work_smoke_portfolio_opened 1
                return 0
            end

            command perl $argv
        end

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 51, \"app\": \"Portfolio Performance\", \"space\": 8, \"display\": 1, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Portfolio Performance\"}
            ]"
        end

        function workspace_find_app_key_window
            argparse "app-key=" "space=" "caller=" no-refresh target-only visible quiet-unmovable -- $argv

            if test "$_flag_app_key" = portfolio_performance
                echo 51
            end
        end

        function resolve_workspace_primary_display
            echo 1
        end

        function ws_query_displays
            printf "%s\n" "[{\"index\":1,\"frame\":{\"x\":0,\"y\":0,\"w\":1800,\"h\":1169}}]"
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
            set -ga __work_smoke_control_moves (string join , -- $argv)
        end

        function ws_window
            set -ga __work_smoke_control_bounds (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        coding_control
        or exit 1

        test "$__work_smoke_portfolio_opened" = 0
        or exit 2

        contains -- "8,51" $__work_smoke_control_moves
        or exit 3

        contains -- "51 --move abs:420:180" $__work_smoke_control_bounds
        or exit 4

        contains -- "51 --resize abs:1220:852" $__work_smoke_control_bounds
        or exit 5
    '
    fish -lc "$coding_control_portfolio_smoke" >/tmp/work-coding-control-portfolio-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      coding control Portfolio Performance optional layout"
    else
        echo "FAIL    coding control Portfolio Performance optional layout"
        cat /tmp/work-coding-control-portfolio-smoke.out
        set failed 1
    end

    set -l coding_control_hidden_flclash_smoke '
        work_reload >/dev/null

        set -g __work_smoke_control_moves
        set -g __work_smoke_control_grids
        set -g __work_smoke_flclash_opened 0

        function perl
            if contains -- open $argv; and contains -- FlClash $argv
                set -g __work_smoke_flclash_opened 1
                return 0
            end

            command perl $argv
        end

        function sleep
        end

        function ws_query_windows
            set -l phase $argv[2]

            switch "$phase"
                case final
                    printf "%s\n" "[
                        {\"id\": 41, \"app\": \"FlClash\", \"space\": 8, \"display\": 1, \"can-move\": true, \"is-minimized\": false, \"is-visible\": false, \"title\": \"FlClash\"}
                    ]"
                case "*"
                    printf "%s\n" "[
                        {\"id\": 41, \"app\": \"FlClash\", \"space\": 5, \"display\": 1, \"can-move\": true, \"is-minimized\": false, \"is-visible\": false, \"title\": \"FlClash\"}
                    ]"
            end
        end

        function workspace_find_app_key_window
            return 0
        end

        function resolve_workspace_primary_display
            echo 1
        end

        function ws_query_displays
            printf "%s\n" "[{\"index\":1,\"frame\":{\"x\":0,\"y\":0,\"w\":1800,\"h\":1169}}]"
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
            set -ga __work_smoke_control_moves (string join , -- $argv)
        end

        function ws_window
            set -ga __work_smoke_control_grids (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        coding_control
        or exit 1

        test "$__work_smoke_flclash_opened" = 0
        or exit 2

        contains -- "8,41" $__work_smoke_control_moves
        or exit 3

        contains -- "41 --move abs:360:120" $__work_smoke_control_grids
        or exit 4

        contains -- "41 --resize abs:1200:1040" $__work_smoke_control_grids
        or exit 5
    '
    fish -lc "$coding_control_hidden_flclash_smoke" >/tmp/work-coding-control-hidden-flclash-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      coding control hidden FlClash no-open capture"
    else
        echo "FAIL    coding control hidden FlClash no-open capture"
        cat /tmp/work-coding-control-hidden-flclash-smoke.out
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

        function ws_query_displays
            printf "%s\n" "[{\"index\":1,\"frame\":{\"x\":0,\"y\":0,\"w\":1800,\"h\":1169}}]"
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

    set -l coding_control_smartgit_failed_move_fallback_smoke '
        work_reload >/dev/null

        set -g __work_smoke_control_fallback_args ""
        set -g __work_smoke_control_moves
        set -g __work_smoke_control_fallback_used 0
        set -g __work_smoke_control_bounds ""

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 21, \"app\": \"Warp\", \"space\": 4, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"Warp\"},
                {\"id\": 22, \"app\": \"SmartGit\", \"space\": 6, \"display\": 1, \"can-move\": true, \"is-minimized\": false, \"is-visible\": true, \"title\": \"SmartGit\"}
            ]"
        end

        function workspace_find_app_key_window
            argparse "app-key=" "space=" "caller=" no-refresh target-only visible quiet-unmovable -- $argv

            switch "$_flag_app_key"
                case warp
                    if set -q _flag_space; and test "$__work_smoke_control_fallback_used" -eq 1; and test "$_flag_space" = 6
                        echo 21
                    else if not set -q _flag_space
                        echo 21
                    end
                    return 0
                case smartgit
                    if set -q _flag_space
                        if test "$__work_smoke_control_fallback_used" -eq 1; and test "$_flag_space" = 6
                            echo 22
                        end
                    else
                        echo 22
                    end
                    return 0
                case keepassx
                    return 0
            end
        end

        function resolve_workspace_primary_display
            echo 2
        end

        function ws_query_displays
            printf "%s\n" "[
                {\"index\": 1, \"frame\": {\"x\": 0, \"y\": 0, \"w\": 3062, \"h\": 1282}},
                {\"index\": 2, \"frame\": {\"x\": 3062, \"y\": 594, \"w\": 1800, \"h\": 1169}}
            ]"
        end

        function find_or_create_labeled_space
            echo 4
        end

        function workspace_retarget_contaminated_space
            echo 4
        end

        function workspace_focus_labeled_space
        end

        function workspace_focus_space_fallback
            set -g __work_smoke_control_fallback_args (string join " " -- $argv)
            set -g __work_smoke_control_fallback_used 1
            echo 6
        end

        function workspace_evict_non_owned_windows_from_space
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_control_moves (string join , -- $argv)
        end

        function ws_window
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

        test "$__work_smoke_control_fallback_used" -eq 1
        or exit 2

        string match -q "*--space 6*" -- "$__work_smoke_control_fallback_args"
        or exit 3

        string match -q "*--source-display 1*" -- "$__work_smoke_control_fallback_args"
        or exit 4

        string match -q "*--target-display 2*" -- "$__work_smoke_control_fallback_args"
        or exit 5

        contains -- "6,21" $__work_smoke_control_moves
        or exit 6

        string match -q "*--x 3362*" -- "$__work_smoke_control_bounds"
        and string match -q "*--y 654*" -- "$__work_smoke_control_bounds"
        or exit 7
    '
    fish -lc "$coding_control_smartgit_failed_move_fallback_smoke" >/tmp/work-coding-control-smartgit-failed-move-fallback-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      coding control SmartGit failed-move fallback"
    else
        echo "FAIL    coding control SmartGit failed-move fallback"
        cat /tmp/work-coding-control-smartgit-failed-move-fallback-smoke.out
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
                        {\"id\": 41, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"},
                        {\"id\": 42, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Meeting\"}
                    ]"
                case teams_any teams_target
                    printf "%s\n" "[]"
                case "*"
                    printf "%s\n" "[
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
            --zoom-grid 1:2:0:0:1:1 \
            --teams-grid 1:2:1:0:1:1
        or exit 1

        contains -- "8,41,42" $__work_smoke_zoom_moves
        or exit 2

        contains -- "41 --grid 1:1:0:0:1:1" $__work_smoke_zoom_grids
        or exit 3

        contains -- "42 --grid 1:1:0:0:1:1" $__work_smoke_zoom_grids
        or exit 4
    '
    fish -lc "$meeting_zoom_settle_smoke" >/tmp/work-meeting-zoom-settle-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      meeting Zoom-only settle full-screen"
    else
        echo "FAIL    meeting Zoom-only settle full-screen"
        cat /tmp/work-meeting-zoom-settle-smoke.out
        set failed 1
    end

    set -l meeting_zoom_alias_smoke '
        work_reload >/dev/null

        set -g __work_smoke_zoom_alias_moves
        set -g __work_smoke_zoom_alias_grids

        function workspace_run_cleanup_specs
        end

        function ws_query_windows
            set -l phase $argv[2]

            switch "$phase"
                case initial zoom_any
                    printf "%s\n" "[
                        {\"id\": 41, \"app\": \"Zoom\", \"space\": 7, \"display\": 1, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"}
                    ]"
                case teams_any teams_target
                    printf "%s\n" "[]"
                case "*"
                    printf "%s\n" "[
                        {\"id\": 41, \"app\": \"Zoom\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"}
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
            set -ga __work_smoke_zoom_alias_moves (string join , -- $argv)
        end

        function ws_window
            set -ga __work_smoke_zoom_alias_grids (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_meeting_space \
            --label gtd_meeting_tall \
            --display tall \
            --zoom-grid 2:1:0:0:1:1 \
            --teams-grid 2:1:0:1:1:1
        or exit 1

        contains -- "8,41" $__work_smoke_zoom_alias_moves
        or exit 2

        contains -- "41 --grid 1:1:0:0:1:1" $__work_smoke_zoom_alias_grids
        or exit 3
    '
    fish -lc "$meeting_zoom_alias_smoke" >/tmp/work-meeting-zoom-alias-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      meeting Zoom alias-only full-screen"
    else
        echo "FAIL    meeting Zoom alias-only full-screen"
        cat /tmp/work-meeting-zoom-alias-smoke.out
        set failed 1
    end

    set -l meeting_teams_settle_smoke '
        work_reload >/dev/null

        set -g __work_smoke_teams_any_calls 0
        set -g __work_smoke_teams_late_visible 0
        set -g __work_smoke_teams_moves
        set -g __work_smoke_teams_grids

        function workspace_run_cleanup_specs
        end

        function sleep
        end

        function ws_query_windows
            set -l phase $argv[2]

            switch "$phase"
                case zoom_any zoom_target
                    printf "%s\n" "[]"
                case teams_any
                    set -g __work_smoke_teams_any_calls (math $__work_smoke_teams_any_calls + 1)
                    if test "$__work_smoke_teams_any_calls" -ge 3
                        printf "%s\n" "[
                            {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams\"},
                            {\"id\": 52, \"app\": \"Microsoft Teams\", \"space\": 9, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams Meeting\"}
                        ]"
                    else
                        printf "%s\n" "[
                            {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams\"}
                        ]"
                    end
                case teams_target
                    if test "$__work_smoke_teams_late_visible" = 1
                        printf "%s\n" "[
                            {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams\"},
                            {\"id\": 52, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams Meeting\"}
                        ]"
                    else
                        printf "%s\n" "[
                            {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams\"}
                        ]"
                    end
                case final_teams_settle_reconcile
                    set -g __work_smoke_teams_late_visible 1
                    printf "%s\n" "[
                        {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams\"},
                        {\"id\": 52, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams Meeting\"}
                    ]"
                case "*"
                    printf "%s\n" "[
                        {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams\"}
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
            set -ga __work_smoke_teams_moves (string join , -- $argv)
        end

        function ws_window
            set -ga __work_smoke_teams_grids (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_meeting_space \
            --label gtd_meeting_wide \
            --display wide \
            --zoom-grid 1:2:0:0:1:1 \
            --teams-grid 1:2:1:0:1:1
        or exit 1

        contains -- "8,51,52" $__work_smoke_teams_moves
        or exit 2

        contains -- "51 --grid 1:1:0:0:1:1" $__work_smoke_teams_grids
        or exit 3

        contains -- "52 --grid 1:1:0:0:1:1" $__work_smoke_teams_grids
        or exit 4
    '
    fish -lc "$meeting_teams_settle_smoke" >/tmp/work-meeting-teams-settle-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      meeting Teams-only settle full-screen"
    else
        echo "FAIL    meeting Teams-only settle full-screen"
        cat /tmp/work-meeting-teams-settle-smoke.out
        set failed 1
    end

    set -l meeting_zoom_teams_split_smoke '
        work_reload >/dev/null

        set -g __work_smoke_meeting_split_moves
        set -g __work_smoke_meeting_split_grids

        function workspace_run_cleanup_specs
        end

        function sleep
        end

        function ws_query_windows
            printf "%s\n" "[
                {\"id\": 41, \"app\": \"zoom.us\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Zoom Workplace\"},
                {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"is-minimized\": false, \"title\": \"Teams\"}
            ]"
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
            set -ga __work_smoke_meeting_split_moves (string join , -- $argv)
        end

        function ws_window
            set -ga __work_smoke_meeting_split_grids (string join " " -- $argv)
        end

        function ws_focus_space
        end

        function cleanup_unlabeled_empty_spaces
        end

        gtd_apply_meeting_space \
            --label gtd_meeting_wide \
            --display wide \
            --zoom-grid 1:2:0:0:1:1 \
            --teams-grid 1:2:1:0:1:1
        or exit 1

        contains -- "8,41,51" $__work_smoke_meeting_split_moves
        or exit 2

        contains -- "41 --grid 1:2:0:0:1:1" $__work_smoke_meeting_split_grids
        or exit 3

        contains -- "51 --grid 1:2:1:0:1:1" $__work_smoke_meeting_split_grids
        or exit 4
    '
    fish -lc "$meeting_zoom_teams_split_smoke" >/tmp/work-meeting-zoom-teams-split-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      meeting Zoom/Teams split layout"
    else
        echo "FAIL    meeting Zoom/Teams split layout"
        cat /tmp/work-meeting-zoom-teams-split-smoke.out
        set failed 1
    end

    set -l meeting_teams_companion_fallback_smoke '
        work_reload >/dev/null

        set -g __work_smoke_teams_companion_fallback_args ""
        set -g __work_smoke_teams_companion_eviction_args ""
        set -g __work_smoke_teams_companion_moves
        set -g __work_smoke_teams_companion_bounds

        function workspace_run_cleanup_specs
        end

        function sleep
        end

        function ws_query_windows
            set -l phase $argv[2]

            switch "$phase"
                case zoom_any zoom_target
                    printf "%s\n" "[]"
                case teams_any teams_unmovable_space_fallback
                    printf "%s\n" "[
                        {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 8, \"display\": 2, \"can-move\": true, \"has-ax-reference\": true, \"is-minimized\": false, \"is-visible\": false, \"title\": \"Teams\"},
                        {\"id\": 52, \"app\": \"MSTeams\", \"space\": 6, \"display\": 1, \"can-move\": false, \"has-ax-reference\": false, \"is-minimized\": false, \"is-visible\": false, \"title\": \"\"}
                    ]"
                case teams_target final final_teams_settle_reconcile
                    printf "%s\n" "[
                        {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 6, \"display\": 2, \"can-move\": true, \"has-ax-reference\": true, \"is-minimized\": false, \"is-visible\": false, \"title\": \"Teams\"},
                        {\"id\": 52, \"app\": \"MSTeams\", \"space\": 6, \"display\": 2, \"can-move\": false, \"has-ax-reference\": false, \"is-minimized\": false, \"is-visible\": false, \"title\": \"\"}
                    ]"
                case "*"
                    printf "%s\n" "[
                        {\"id\": 51, \"app\": \"Microsoft Teams\", \"space\": 6, \"display\": 2, \"can-move\": true, \"has-ax-reference\": true, \"is-minimized\": false, \"is-visible\": false, \"title\": \"Teams\"},
                        {\"id\": 52, \"app\": \"MSTeams\", \"space\": 6, \"display\": 2, \"can-move\": false, \"has-ax-reference\": false, \"is-minimized\": false, \"is-visible\": false, \"title\": \"\"}
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
            set -g __work_smoke_teams_companion_fallback_args (string join " " -- $argv)
            echo 6
        end

        function workspace_evict_non_owned_windows_from_space
            set -g __work_smoke_teams_companion_eviction_args (string join " " -- $argv)
        end

        function ws_move_windows_to_space
            set -ga __work_smoke_teams_companion_moves (string join , -- $argv)
        end

        function workspace_apply_app_key_grid_bounds
            set -ga __work_smoke_teams_companion_bounds (string join " " -- $argv)
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
            --zoom-grid 1:2:0:0:1:1 \
            --teams-grid 1:2:1:0:1:1
        or exit 1

        string match -q "*--space 6*" -- "$__work_smoke_teams_companion_fallback_args"
        or exit 2

        contains -- "6,51" $__work_smoke_teams_companion_moves
        or exit 3

        string match -q "*--app-key teams*--all-windows*" -- "$__work_smoke_teams_companion_bounds"
        or exit 4
    '
    fish -lc "$meeting_teams_companion_fallback_smoke" >/tmp/work-meeting-teams-companion-fallback-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      meeting Teams non-AX companion fallback"
    else
        echo "FAIL    meeting Teams non-AX companion fallback"
        cat /tmp/work-meeting-teams-companion-fallback-smoke.out
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
            --zoom-grid 1:2:0:0:1:1 \
            --teams-grid 1:2:1:0:1:1
        or exit 1

        test "$__work_smoke_zoom_fallback_called" = 1
        or exit 2

        contains -- "8,51" $__work_smoke_meeting_moves
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

    set -l yabai_doctor_usage_smoke '
        work_reload >/dev/null
        yabai_doctor --unknown >/tmp/yabai-doctor-usage.out 2>&1
        test $status -eq 2
        or exit 1
        string match -q "usage: yabai_doctor [--repair]" \
            (cat /tmp/yabai-doctor-usage.out)
        or exit 2
    '
    fish -lc "$yabai_doctor_usage_smoke"
    if test $status -eq 0
        echo "OK      yabai doctor rejects unsupported options"
    else
        echo "FAIL    yabai doctor rejects unsupported options"
        set failed 1
    end

    set -l yabai_doctor_dispatch_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_check_calls 0
        set -g __yabai_doctor_repair_calls 0

        function __yabai_doctor_check
            set -g __yabai_doctor_check_calls \
                (math $__yabai_doctor_check_calls + 1)
        end

        function __yabai_doctor_repair
            set -g __yabai_doctor_repair_calls \
                (math $__yabai_doctor_repair_calls + 1)
        end

        yabai_doctor >/dev/null
        or exit 1
        test "$__yabai_doctor_check_calls" -eq 1
        or exit 2
        test "$__yabai_doctor_repair_calls" -eq 0
        or exit 3

        yabai_doctor --repair >/dev/null
        or exit 4
        test "$__yabai_doctor_check_calls" -eq 1
        or exit 5
        test "$__yabai_doctor_repair_calls" -eq 1
        or exit 6
    '
    fish -lc "$yabai_doctor_dispatch_smoke"
    if test $status -eq 0
        echo "OK      yabai doctor dispatch"
    else
        echo "FAIL    yabai doctor dispatch"
        set failed 1
    end

    set -l yabai_doctor_readonly_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_mutations

        function __yabai_doctor_binary_path
            echo /opt/homebrew/bin/yabai
        end

        function __yabai_doctor_real_path
            echo /opt/homebrew/Cellar/yabai/HEAD-test/bin/yabai
        end

        function __yabai_doctor_sha256
            echo abc123
        end

        function __yabai_doctor_version
            echo yabai-vHEAD
        end

        function __yabai_doctor_loaded_service
            echo gui/501/com.asmvik.yabai
        end

        function __yabai_doctor_service_running
            return 0
        end

        function __yabai_doctor_sudo_rule_matches
            return 0
        end

        function __yabai_doctor_queries
            printf "%s\n" displays=2 spaces=5 windows=12
        end

        function __yabai_doctor_ensure_head
            set -ga __yabai_doctor_mutations ensure_head
        end

        function __yabai_doctor_install_sudoers
            set -ga __yabai_doctor_mutations install_sudoers
        end

        function ws_restart_yabai
            set -ga __yabai_doctor_mutations restart
        end

        set -l output (yabai_doctor 2>/tmp/yabai-doctor-readonly.err)
        or exit 1

        test ! -s /tmp/yabai-doctor-readonly.err
        or exit 2

        test (count $__yabai_doctor_mutations) -eq 0
        or exit 3

        string match -q "*HEAD build active*" -- $output
        or exit 4

        string match -q "*sudoers hash matches*" -- $output
        or exit 5

        string match -q "*LaunchAgent running*" -- $output
        or exit 6
    '
    fish -lc "$yabai_doctor_readonly_smoke" >/tmp/work-yabai-doctor-readonly-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor default is read-only"
    else
        echo "FAIL    yabai doctor default is read-only"
        cat /tmp/work-yabai-doctor-readonly-smoke.out
        set failed 1
    end

    set -l yabai_doctor_stale_sudoers_smoke '
        work_reload >/dev/null

        function __yabai_doctor_binary_path
            echo /opt/homebrew/bin/yabai
        end

        function __yabai_doctor_real_path
            echo /opt/homebrew/Cellar/yabai/HEAD-test/bin/yabai
        end

        function __yabai_doctor_sha256
            echo stale123
        end

        function __yabai_doctor_version
            echo yabai-vHEAD
        end

        function __yabai_doctor_loaded_service
            echo gui/501/com.asmvik.yabai
        end

        function __yabai_doctor_service_running
            return 0
        end

        function __yabai_doctor_sudo_rule_matches
            return 1
        end

        function __yabai_doctor_queries
            printf "%s\n" displays=2 spaces=5 windows=12
        end

        set -l output (yabai_doctor)
        set -l doctor_status $status

        test "$doctor_status" -eq 1
        or exit 1

        string match -q "FAIL    sudoers hash does not match" -- $output
        or exit 2
    '
    fish -lc "$yabai_doctor_stale_sudoers_smoke" >/tmp/work-yabai-doctor-stale-sudoers-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor detects stale sudoers hash"
    else
        echo "FAIL    yabai doctor detects stale sudoers hash"
        cat /tmp/work-yabai-doctor-stale-sudoers-smoke.out
        set failed 1
    end

    set -l yabai_doctor_sudoers_rule_smoke '
        work_reload >/dev/null

        function sudo
            test "$argv[1]" = -n
            or return 1
            test "$argv[2]" = -l
            or return 1
            echo "(root) NOPASSWD: sha256:abc123 /opt/homebrew/bin/yabai --load-sa"
        end

        __yabai_doctor_sudo_rule_matches \
            /opt/homebrew/bin/yabai \
            abc123
    '
    fish -lc "$yabai_doctor_sudoers_rule_smoke" >/tmp/work-yabai-doctor-sudoers-rule-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor parses sudoers rule"
    else
        echo "FAIL    yabai doctor parses sudoers rule"
        cat /tmp/work-yabai-doctor-sudoers-rule-smoke.out
        set failed 1
    end

    set -l yabai_doctor_repair_order_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_repair_order

        function __yabai_doctor_ensure_head
            set -ga __yabai_doctor_repair_order ensure_head
        end

        function __yabai_doctor_install_sudoers
            set -ga __yabai_doctor_repair_order install_sudoers
        end

        function __yabai_doctor_load_sa
            set -ga __yabai_doctor_repair_order load_sa
        end

        function ws_restart_yabai
            set -ga __yabai_doctor_repair_order restart
        end

        function sleep
        end

        function __yabai_doctor_queries
            set -ga __yabai_doctor_repair_order query
        end

        function __yabai_doctor_space_probe
            set -ga __yabai_doctor_repair_order space_probe
        end

        function work_doctor
            set -ga __yabai_doctor_repair_order work_doctor
        end

        function __yabai_doctor_check
            set -ga __yabai_doctor_repair_order final_check
        end

        yabai_doctor --repair >/dev/null
        or exit 1

        test (string join " " -- $__yabai_doctor_repair_order) = \
            "ensure_head install_sudoers load_sa restart query space_probe work_doctor final_check"
    '
    fish -lc "$yabai_doctor_repair_order_smoke" >/tmp/work-yabai-doctor-repair-order-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor repair dependency order"
    else
        echo "FAIL    yabai doctor repair dependency order"
        cat /tmp/work-yabai-doctor-repair-order-smoke.out
        set failed 1
    end

    set -l yabai_doctor_accessibility_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_accessibility_opened 0
        set -g __yabai_doctor_space_probe_calls 0

        function __yabai_doctor_ensure_head
        end

        function __yabai_doctor_install_sudoers
        end

        function __yabai_doctor_load_sa
        end

        function ws_restart_yabai
        end

        function sleep
        end

        function __yabai_doctor_queries
            return 1
        end

        function __yabai_doctor_accessibility_missing
            return 0
        end

        function __yabai_doctor_open_accessibility
            set -g __yabai_doctor_accessibility_opened 1
        end

        function __yabai_doctor_space_probe
            set -g __yabai_doctor_space_probe_calls \
                (math $__yabai_doctor_space_probe_calls + 1)
        end

        yabai_doctor --repair >/dev/null
        test $status -eq 1
        or exit 1

        test "$__yabai_doctor_accessibility_opened" -eq 1
        or exit 2

        test "$__yabai_doctor_space_probe_calls" -eq 0
        or exit 3
    '
    fish -lc "$yabai_doctor_accessibility_smoke" >/tmp/work-yabai-doctor-accessibility-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor hands off Accessibility"
    else
        echo "FAIL    yabai doctor hands off Accessibility"
        cat /tmp/work-yabai-doctor-accessibility-smoke.out
        set failed 1
    end

    set -l yabai_doctor_head_install_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_head_phase stable
        set -g __yabai_doctor_brew_calls

        function __yabai_doctor_binary_path
            echo /opt/homebrew/bin/yabai
        end

        function __yabai_doctor_real_path
            if test "$__yabai_doctor_head_phase" = stable
                echo /opt/homebrew/Cellar/yabai/7.1.25/bin/yabai
            else
                echo /opt/homebrew/Cellar/yabai/HEAD-test/bin/yabai
            end
        end

        function brew
            set -ga __yabai_doctor_brew_calls (string join " " -- $argv)

            if test "$argv[1]" = install
                set -g __yabai_doctor_head_phase head
            end
        end

        __yabai_doctor_ensure_head >/dev/null
        or exit 1

        contains -- "list --versions yabai" $__yabai_doctor_brew_calls
        or exit 2

        contains -- "unlink yabai" $__yabai_doctor_brew_calls
        or exit 3

        contains -- "install --HEAD asmvik/formulae/yabai" $__yabai_doctor_brew_calls
        or exit 4
    '
    fish -lc "$yabai_doctor_head_install_smoke" >/tmp/work-yabai-doctor-head-install-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor activates Homebrew HEAD"
    else
        echo "FAIL    yabai doctor activates Homebrew HEAD"
        cat /tmp/work-yabai-doctor-head-install-smoke.out
        set failed 1
    end

    set -l yabai_doctor_visudo_guard_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_install_calls 0
        set -g __yabai_doctor_validated_path

        function __yabai_doctor_binary_path
            echo /opt/homebrew/bin/yabai
        end

        function __yabai_doctor_sha256
            echo abc123
        end

        function __yabai_doctor_validate_sudoers
            set -g __yabai_doctor_validated_path $argv[1]
            return 1
        end

        function __yabai_doctor_install_sudoers_file
            set -g __yabai_doctor_install_calls \
                (math $__yabai_doctor_install_calls + 1)
        end

        __yabai_doctor_install_sudoers >/dev/null 2>&1
        test $status -eq 1
        or exit 1

        test "$__yabai_doctor_install_calls" -eq 0
        or exit 2

        test -n "$__yabai_doctor_validated_path"
        or exit 3

        test ! -e "$__yabai_doctor_validated_path"
        or exit 4
    '
    fish -lc "$yabai_doctor_visudo_guard_smoke" >/tmp/work-yabai-doctor-visudo-guard-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor blocks invalid sudoers"
    else
        echo "FAIL    yabai doctor blocks invalid sudoers"
        cat /tmp/work-yabai-doctor-visudo-guard-smoke.out
        set failed 1
    end

    set -l yabai_doctor_sudoers_content_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_sudoers_content
        set -g __yabai_doctor_installed_path

        function __yabai_doctor_binary_path
            echo /opt/homebrew/bin/yabai
        end

        function __yabai_doctor_sha256
            echo abc123
        end

        function whoami
            echo testuser
        end

        function __yabai_doctor_validate_sudoers
        end

        function __yabai_doctor_install_sudoers_file
            set -g __yabai_doctor_installed_path $argv[1]
            set -g __yabai_doctor_sudoers_content (cat "$argv[1]")
        end

        __yabai_doctor_install_sudoers >/dev/null
        or exit 1

        test "$__yabai_doctor_sudoers_content" = \
            "testuser ALL=(root) NOPASSWD: sha256:abc123 /opt/homebrew/bin/yabai --load-sa"
        or exit 2

        test ! -e "$__yabai_doctor_installed_path"
        or exit 3
    '
    fish -lc "$yabai_doctor_sudoers_content_smoke" >/tmp/work-yabai-doctor-sudoers-content-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor writes hash-bound sudoers"
    else
        echo "FAIL    yabai doctor writes hash-bound sudoers"
        cat /tmp/work-yabai-doctor-sudoers-content-smoke.out
        set failed 1
    end

    set -l yabai_doctor_load_sa_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_sudo_calls

        function __yabai_doctor_binary_path
            echo /opt/homebrew/bin/yabai
        end

        function sudo
            set -ga __yabai_doctor_sudo_calls (string join " " -- $argv)
        end

        __yabai_doctor_load_sa >/dev/null
        or exit 1

        test "$__yabai_doctor_sudo_calls" = \
            "-n /opt/homebrew/bin/yabai --load-sa"
    '
    fish -lc "$yabai_doctor_load_sa_smoke" >/tmp/work-yabai-doctor-load-sa-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor loads scripting addition"
    else
        echo "FAIL    yabai doctor loads scripting addition"
        cat /tmp/work-yabai-doctor-load-sa-smoke.out
        set failed 1
    end

    set -l yabai_doctor_space_probe_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_space_calls

        function sleep
        end

        function ws_query_spaces
            switch "$argv[1]"
                case yabai_doctor_space_before
                    echo "[{\"uuid\":\"A\",\"index\":1},{\"uuid\":\"B\",\"index\":2}]"
                case yabai_doctor_space_after
                    echo "[{\"uuid\":\"A\",\"index\":1},{\"uuid\":\"B\",\"index\":2},{\"uuid\":\"C\",\"index\":3}]"
                case yabai_doctor_space_final
                    echo "[{\"uuid\":\"A\",\"index\":1},{\"uuid\":\"B\",\"index\":2}]"
                case "*"
                    return 1
            end
        end

        function ws_yabai
            set -ga __yabai_doctor_space_calls (string join " " -- $argv)
        end

        __yabai_doctor_space_probe >/dev/null
        or exit 1

        contains -- "-m space --create" $__yabai_doctor_space_calls
        or exit 2

        contains -- "-m space --destroy 3" $__yabai_doctor_space_calls
        or exit 3

        test (count $__yabai_doctor_space_calls) -eq 2
        or exit 4
    '
    fish -lc "$yabai_doctor_space_probe_smoke" >/tmp/work-yabai-doctor-space-probe-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor destroys only new Space"
    else
        echo "FAIL    yabai doctor destroys only new Space"
        cat /tmp/work-yabai-doctor-space-probe-smoke.out
        set failed 1
    end

    set -l yabai_doctor_space_missing_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_destroy_calls 0

        function sleep
        end

        function ws_query_spaces
            echo "[{\"uuid\":\"A\",\"index\":1},{\"uuid\":\"B\",\"index\":2}]"
        end

        function ws_yabai
            if contains -- --destroy $argv
                set -g __yabai_doctor_destroy_calls \
                    (math $__yabai_doctor_destroy_calls + 1)
            end
        end

        __yabai_doctor_space_probe >/dev/null 2>&1
        test $status -eq 1
        or exit 1

        test "$__yabai_doctor_destroy_calls" -eq 0
        or exit 2
    '
    fish -lc "$yabai_doctor_space_missing_smoke" >/tmp/work-yabai-doctor-space-missing-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor preserves Spaces when creation is unobserved"
    else
        echo "FAIL    yabai doctor preserves Spaces when creation is unobserved"
        cat /tmp/work-yabai-doctor-space-missing-smoke.out
        set failed 1
    end

    set -l yabai_doctor_space_ambiguous_smoke '
        work_reload >/dev/null
        set -g __yabai_doctor_destroy_calls 0

        function sleep
        end

        function ws_query_spaces
            if test "$argv[1]" = yabai_doctor_space_before
                echo "[{\"uuid\":\"A\",\"index\":1},{\"uuid\":\"B\",\"index\":2}]"
            else
                echo "[{\"uuid\":\"A\",\"index\":1},{\"uuid\":\"B\",\"index\":2},{\"uuid\":\"C\",\"index\":3},{\"uuid\":\"D\",\"index\":4}]"
            end
        end

        function ws_yabai
            if contains -- --destroy $argv
                set -g __yabai_doctor_destroy_calls \
                    (math $__yabai_doctor_destroy_calls + 1)
            end
        end

        __yabai_doctor_space_probe >/dev/null 2>&1
        test $status -eq 1
        or exit 1

        test "$__yabai_doctor_destroy_calls" -eq 0
        or exit 2
    '
    fish -lc "$yabai_doctor_space_ambiguous_smoke" >/tmp/work-yabai-doctor-space-ambiguous-smoke.out 2>&1
    if test $status -eq 0
        echo "OK      yabai doctor preserves ambiguous Spaces"
    else
        echo "FAIL    yabai doctor preserves ambiguous Spaces"
        cat /tmp/work-yabai-doctor-space-ambiguous-smoke.out
        set failed 1
    end

    set -l dry_run_commands (workspace_dry_run_commands)

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

    functions -e fish
    if test "$had_fish_function" -eq 1
        functions -c __spacewright_saved_fish_function fish
        functions -e __spacewright_saved_fish_function
    end

    return $failed
end

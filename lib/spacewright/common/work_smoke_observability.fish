function work_smoke_observability --description "Run focused workspace observability and label-recovery smoke checks"
    set -l smoke_script '
        work_reload >/dev/null

        set -g __work_smoke_observation_fixture meeting_unlabeled
        set -g __work_smoke_observation_label_mutations 0
        set -g __work_smoke_observation_unsafe_mutations 0
        set -g __work_smoke_observation_last_label_args ""
        set -g __work_smoke_observation_meeting_label_applied 0

        function ws_query_displays
            printf "%s\n" "[
                {\"index\":1,\"uuid\":\"primary\",\"frame\":{\"x\":0,\"y\":0,\"w\":1800,\"h\":1169}},
                {\"index\":2,\"uuid\":\"external-wide\",\"frame\":{\"x\":-3062,\"y\":-594,\"w\":3062,\"h\":1282}}
            ]"
        end

        function ws_query_spaces
            switch "$__work_smoke_observation_fixture"
                case meeting_unlabeled meeting_foreign
                    set -l meeting_label ""
                    if test "$__work_smoke_observation_meeting_label_applied" -eq 1
                        set meeting_label gtd_meeting_wide
                    end
                    printf "%s\n" "[
                        {\"index\":4,\"display\":1,\"label\":\"coding_control\",\"windows\":[]},
                        {\"index\":8,\"display\":2,\"label\":\"$meeting_label\",\"windows\":[41,51]}
                    ]"
                case meeting_split
                    printf "%s\n" "[
                        {\"index\":7,\"display\":2,\"label\":\"\",\"windows\":[41]},
                        {\"index\":8,\"display\":2,\"label\":\"\",\"windows\":[51]}
                    ]"
                case all_mixed
                    printf "%s\n" "[
                        {\"index\":4,\"display\":1,\"label\":\"\",\"windows\":[21]},
                        {\"index\":8,\"display\":2,\"label\":\"gtd_meeting_wide\",\"windows\":[41,51]}
                    ]"
                case inactive
                    printf "%s\n" "[
                        {\"index\":4,\"display\":1,\"label\":\"\",\"windows\":[]},
                        {\"index\":8,\"display\":2,\"label\":\"\",\"windows\":[]}
                    ]"
            end
        end

        function ws_query_windows
            switch "$__work_smoke_observation_fixture"
                case meeting_unlabeled
                    printf "%s\n" "[
                        {\"id\":41,\"app\":\"Zoom\",\"title\":\"Zoom Workplace\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-3058,\"y\":-559,\"w\":1525,\"h\":1243}},
                        {\"id\":51,\"app\":\"Microsoft Teams\",\"title\":\"Teams Meeting\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-1529,\"y\":-559,\"w\":1525,\"h\":1243}}
                    ]"
                case meeting_split
                    printf "%s\n" "[
                        {\"id\":41,\"app\":\"Zoom\",\"title\":\"Zoom Workplace\",\"space\":7,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-3058,\"y\":-559,\"w\":1525,\"h\":1243}},
                        {\"id\":51,\"app\":\"Microsoft Teams\",\"title\":\"Teams Meeting\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-1529,\"y\":-559,\"w\":1525,\"h\":1243}}
                    ]"
                case meeting_foreign
                    printf "%s\n" "[
                        {\"id\":41,\"app\":\"Zoom\",\"title\":\"Zoom Workplace\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-3058,\"y\":-559,\"w\":1525,\"h\":1243}},
                        {\"id\":51,\"app\":\"Microsoft Teams\",\"title\":\"Teams Meeting\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-1529,\"y\":-559,\"w\":1525,\"h\":1243}},
                        {\"id\":61,\"app\":\"Safari\",\"title\":\"Safari\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":0,\"y\":0,\"w\":800,\"h\":600}}
                    ]"
                case all_mixed
                    printf "%s\n" "[
                        {\"id\":21,\"app\":\"Warp\",\"title\":\"Warp\",\"space\":4,\"display\":1,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":4,\"y\":44,\"w\":1792,\"h\":745}},
                        {\"id\":41,\"app\":\"Zoom\",\"title\":\"Zoom Workplace\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-3058,\"y\":-559,\"w\":1525,\"h\":1243}},
                        {\"id\":51,\"app\":\"Microsoft Teams\",\"title\":\"Teams Meeting\",\"space\":8,\"display\":2,\"can-move\":true,\"is-minimized\":false,\"frame\":{\"x\":-1529,\"y\":-559,\"w\":1525,\"h\":1243}}
                    ]"
                case inactive
                    printf "%s\n" "[]"
            end
        end

        function get_workspace_primary_display_uuid
            echo primary
        end

        function ws_yabai
            if test (count $argv) -eq 5
                    and test "$argv[1]" = -m
                    and test "$argv[2]" = space
                    and test "$argv[4]" = --label
                set -g __work_smoke_observation_label_mutations (math $__work_smoke_observation_label_mutations + 1)
                set -g __work_smoke_observation_last_label_args (string join " " -- $argv)
                if test "$argv[3]" = 8 -a "$argv[5]" = gtd_meeting_wide
                    set -g __work_smoke_observation_meeting_label_applied 1
                end
                return 0
            end

            set -g __work_smoke_observation_unsafe_mutations (math $__work_smoke_observation_unsafe_mutations + 1)
            return 1
        end

        set -l recovery_plan (workspace_restore_labels --json gtd_meeting_wide)
        or exit 1
        printf "%s\n" "$recovery_plan" | ws_jq -e "
            .read_only == true
            and .apply_requested == false
            and (.results | length) == 1
            and .results[0].workspace == \"gtd_meeting_wide\"
            and .results[0].status == \"ready\"
            and .results[0].candidate_space == 8
            and .results[0].applied == false
        " >/dev/null
        or exit 2
        test "$__work_smoke_observation_label_mutations" -eq 0
        or exit 3

        set -g __work_smoke_observation_fixture meeting_split
        set -l split_plan (workspace_restore_labels --json gtd_meeting_wide)
        or exit 4
        printf "%s\n" "$split_plan" | ws_jq -e "
            .results[0].status == \"blocked_ambiguous_space\"
            and .results[0].candidate_space == null
            and (.results[0].candidate_spaces == [7,8])
        " >/dev/null
        or exit 5

        set -g __work_smoke_observation_fixture meeting_foreign
        set -l foreign_plan (workspace_restore_labels --json gtd_meeting_wide)
        or exit 6
        printf "%s\n" "$foreign_plan" | ws_jq -e "
            .results[0].status == \"blocked_foreign_windows\"
            and (.results[0].foreign_window_ids == [61])
        " >/dev/null
        or exit 7

        set -l blocked_apply (workspace_restore_labels --apply --json gtd_meeting_wide coding_control)
        set -l blocked_apply_status $status
        test "$blocked_apply_status" -ne 0
        or exit 16
        printf "%s\n" "$blocked_apply" | ws_jq -e "
            .status == \"blocked\"
            and .ok == false
            and (first(.results[] | select(.workspace == \"gtd_meeting_wide\") | .status) == \"blocked_foreign_windows\")
            and (first(.results[] | select(.workspace == \"coding_control\") | .status) == \"already_labeled\")
        " >/dev/null
        and test "$__work_smoke_observation_label_mutations" -eq 0
        or exit 17

        set -g __work_smoke_observation_fixture meeting_unlabeled
        set -l recovery_apply (workspace_restore_labels --apply --json gtd_meeting_wide)
        or exit 8
        printf "%s\n" "$recovery_apply" | ws_jq -e "
            .read_only == false
            and .apply_requested == true
            and .results[0].status == \"restored\"
            and .results[0].applied == true
        " >/dev/null
        or exit 9
        test "$__work_smoke_observation_label_mutations" -eq 1
        and test "$__work_smoke_observation_last_label_args" = "-m space 8 --label gtd_meeting_wide"
        and test "$__work_smoke_observation_unsafe_mutations" -eq 0
        or exit 10

        set -g __work_smoke_observation_fixture all_mixed
        set -l all_verify (workspace_verify --all --json)
        set -l all_verify_status $status
        test "$all_verify_status" -ne 0
        or exit 11
        printf "%s\n" "$all_verify" | ws_jq -e "
            .read_only == true
            and .status == \"drift\"
            and .ok == false
            and (.results | length) > 2
            and (first(.results[] | select(.workspace == \"gtd_meeting_wide\") | .status) == \"satisfied\")
            and (first(.results[] | select(.workspace == \"coding_control\") | .status) == \"drift\")
            and all(.results[] | select(.workspace != \"gtd_meeting_wide\" and .workspace != \"coding_control\"); .status == \"not_applicable\")
        " >/dev/null
        or exit 12

        set -g __work_smoke_observation_fixture inactive
        set -l inactive_verify (workspace_verify --all --json)
        or exit 13
        printf "%s\n" "$inactive_verify" | ws_jq -e "
            .status == \"not_applicable\"
            and .ok == true
            and all(.results[]; .status == \"not_applicable\")
        " >/dev/null
        or exit 14

        test "$__work_smoke_observation_label_mutations" -eq 1
        and test "$__work_smoke_observation_unsafe_mutations" -eq 0
        or exit 15
    '

    fish -lc "$smoke_script" >/tmp/work-observability-recovery-smoke.out 2>&1
    set -l smoke_status $status
    if test "$smoke_status" -eq 0
        echo "OK      workspace observability recovery"
    else
        echo "FAIL    workspace observability recovery"
        cat /tmp/work-observability-recovery-smoke.out
    end

    return $smoke_status
end

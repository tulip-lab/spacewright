function workspace_status_snapshot --description "Print common display and space status sections"
    set -l displays_json (ws_query_displays workspace_status_snapshot status)
    if test $status -ne 0 -o -z "$displays_json"
        set displays_json "[]"
    end

    set -l spaces_json (ws_query_spaces workspace_status_snapshot status)
    if test $status -ne 0 -o -z "$spaces_json"
        set spaces_json "[]"
    end

    echo "===== DISPLAYS ====="
    echo $displays_json | ws_jq '.[] | {
        index,
        uuid,
        frame,
        has_focus: .["has-focus"],
        space_count: (.spaces | length),
        spaces
    }'

    echo
    echo "===== SPACES ====="
    echo $spaces_json | ws_jq '.[] | {
        index,
        label,
        display,
        window_count: (.windows | length),
        windows
    }'
end

function workspace_mode_status_section --description "Print labeled spaces matching a mode regex"
    set -l title $argv[1]
    set -l label_pattern $argv[2]

    if test -z "$title" -o -z "$label_pattern"
        return 1
    end

    echo "===== $title ====="
    set -l spaces_json (ws_query_spaces workspace_mode_status_section status)
    if test $status -ne 0 -o -z "$spaces_json"
        return 1
    end

    echo $spaces_json | ws_jq --arg pattern "$label_pattern" '
        .[]
        | select(.label | test($pattern))
        | {
            index,
            label,
            display,
            window_count: (.windows | length),
            windows
        }'
end

function workspace_print_app_status --description "Print status rows for windows matching workspace app keys"
    argparse 'title=' 'caller=' -- $argv
    or return 1

    if not set -q _flag_title; or test (count $argv) -eq 0
        echo "usage: workspace_print_app_status --title <heading> [--caller <name>] <app-key ...>" >&2
        return 2
    end

    set -l caller workspace_print_app_status
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l apps_json (workspace_app_names_json $argv)
    or return 1

    echo
    echo "===== $_flag_title ====="
    set -l windows_json (ws_query_windows $caller status)
    or return 1

    echo $windows_json | ws_jq --argjson apps "$apps_json" '
        .[]
        | select(.app as $app | $apps | index($app))
        | {
            id,
            app,
            title,
            space,
            is_visible: .["is-visible"],
            is_minimized: .["is-minimized"]
        }'
end

function workspace_simple_module_status --description "Print a standard module status snapshot and app list"
    set -l caller $argv[1]
    set -l title $argv[2]
    set -l app_keys $argv[3..-1]

    if test -z "$caller" -o -z "$title" -o (count $app_keys) -eq 0
        echo "usage: workspace_simple_module_status <caller> <title> <app-key>..." >&2
        return 2
    end

    if test "$WORKSPACE_SKIP_STATUS_SNAPSHOT" != "1"
        workspace_status_snapshot
    end

    workspace_print_app_status --title "$title" --caller "$caller" $app_keys
end

function coding_status --description "Show display, space and coding application status"
    workspace_simple_module_status coding_status "CODING APPS" code chatgpt warp smartgit keepassx flclash thaw portfolio_performance
end

function office_status --description "Show display, space and office application status"
    workspace_simple_module_status office_status "OFFICE APPS" word powerpoint chatgpt
end

function research_status --description "Show display, space and research application status"
    workspace_simple_module_status research_status "RESEARCH APPS" zotero chatgpt claude
end

function work_status
    echo "===== WORKSPACE DIAGNOSTICS ====="
    work_diagnostics

    echo
    echo "===== WORKSPACE SNAPSHOT ====="
    workspace_status_snapshot

    set -l had_skip_status_snapshot 0
    set -l previous_skip_status_snapshot

    if set -q WORKSPACE_SKIP_STATUS_SNAPSHOT
        set had_skip_status_snapshot 1
        set previous_skip_status_snapshot $WORKSPACE_SKIP_STATUS_SNAPSHOT
    end

    set -g WORKSPACE_SKIP_STATUS_SNAPSHOT 1

    echo "===== GTD ====="
    gtd_status

    echo
    echo "===== CODING ====="
    coding_status

    echo
    echo "===== OFFICE ====="
    office_status

    echo
    echo "===== RESEARCH ====="
    research_status

    if test "$had_skip_status_snapshot" -eq 1
        set -g WORKSPACE_SKIP_STATUS_SNAPSHOT $previous_skip_status_snapshot
    else
        set -e WORKSPACE_SKIP_STATUS_SNAPSHOT
    end
end

function work_mode_status
    echo "===== GTD MODE STATUS ====="
    workspace_mode_status_section "GTD SOLO SPACES" '^gtd_.*_solo$'
    echo
    workspace_mode_status_section "GTD WIDE SPACES" '^gtd_.*_wide$'
    echo
    workspace_mode_status_section "GTD TALL SPACES" '^gtd_.*_tall$'
    echo
    workspace_mode_status_section "GTD UNSUFFIXED SPACES" '^(gtd_ai|gtd_chat|gtd_calendar)$'

    echo
    echo "===== CODING MODE STATUS ====="
    workspace_mode_status_section "CODING SOLO SPACES" '^coding_.*_solo$'
    echo
    workspace_mode_status_section "CODING WIDE SPACES" '^coding_.*_wide$'
    echo
    workspace_mode_status_section "CODING TALL SPACES" '^coding_.*_tall$'
    echo
    workspace_mode_status_section "CODING INTERNAL SPACES" '^coding_control$'

    echo
    echo "===== OFFICE MODE STATUS ====="
    workspace_mode_status_section "OFFICE SOLO SPACES" '^office_.*_solo$'
    echo
    workspace_mode_status_section "OFFICE WIDE SPACES" '^office_.*_wide$'
    echo
    workspace_mode_status_section "OFFICE TALL SPACES" '^office_.*_tall$'

    echo
    echo "===== RESEARCH MODE STATUS ====="
    workspace_mode_status_section "RESEARCH SOLO SPACES" '^research(_.*)?_solo$'
    echo
    workspace_mode_status_section "RESEARCH WIDE SPACES" '^research(_.*)?_wide$'
    echo
    workspace_mode_status_section "RESEARCH TALL SPACES" '^research(_.*)?_tall$'
end

function work_check --description "Run workspace reload and mode-status checks"
    echo "===== RELOAD ====="
    gtd_reload
    coding_reload
    office_reload
    research_reload

    echo
    echo "===== WORKSPACE DIAGNOSTICS ====="
    work_diagnostics

    echo
    work_mode_status

    echo
    echo "===== OBSERVED WORKSPACES ====="
    workspace_verify --all
    or true
end

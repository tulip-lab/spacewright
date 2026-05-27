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

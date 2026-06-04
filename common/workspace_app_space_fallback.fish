function workspace_app_key_space_fallback_info --description "Return a present app-key window id, space and display for space fallback"
    argparse 'app-key=' 'caller=' 'phase=' visible -- $argv
    or return 1

    if not set -q _flag_app_key
        echo "usage: workspace_app_key_space_fallback_info --app-key <key> [--caller <name>] [--phase <query-phase>] [--visible]" >&2
        return 2
    end

    set -l caller workspace_app_key_space_fallback_info
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l phase app_key_space_fallback
    if set -q _flag_phase
        set phase $_flag_phase
    end

    set -l apps_json (workspace_app_names_json $_flag_app_key)
    or return 1
    set -l visible 0
    if set -q _flag_visible
        set visible 1
    end

    set -l windows_json (ws_query_windows $caller $phase)
    or return 1

    set -l fallback_info (echo $windows_json | ws_jq -r --argjson apps "$apps_json" --arg visible "$visible" '
        first(
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.["is-minimized"]==false)
            | select(($visible!="1") or (.["is-visible"]==true))
            | [.id, .space, .display]
            | @tsv
        ) // empty
    ')
    set -l jq_status $status

    if test "$jq_status" -ne 0
        return $jq_status
    end

    if test -z "$fallback_info"
        return 2
    end

    set -l fallback_parts (string split \t -- "$fallback_info")
    set -l window_id $fallback_parts[1]
    set -l target_space $fallback_parts[2]
    set -l source_display $fallback_parts[3]

    if test -z "$window_id" -o -z "$target_space" -o -z "$source_display"
        return 2
    end

    printf "%s\t%s\t%s\n" "$window_id" "$target_space" "$source_display"
end

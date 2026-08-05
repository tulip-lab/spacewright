function workspace_home_space_info --description "Return the leftmost unlabeled Home UUID and index"
    argparse 'display=' -- $argv
    or return 1

    if not set -q _flag_display
        echo "usage: workspace_home_space_info --display <index>" >&2
        return 2
    end

    set -l spaces_json
    read -lz spaces_json

    echo $spaces_json | ws_jq -r --argjson display $_flag_display '
        [.[] | select(.display==$display and .label=="")]
        | sort_by(.index)
        | first
        | if . == null then empty else [.uuid, (.index|tostring)] | @tsv end
    '
end

function workspace_sandbox_candidate_window_ids --description "Select movable unmanaged windows outside Home"
    argparse 'home-space=' -- $argv
    or return 1

    if not set -q _flag_home_space
        echo "usage: workspace_sandbox_candidate_window_ids --home-space <index>" >&2
        return 2
    end

    set -l windows_json
    read -lz windows_json
    set -l owned_apps (workspace_owned_app_names_json)
    or return 1

    echo $windows_json | ws_jq -r --argjson home $_flag_home_space --argjson owned "$owned_apps" '
        .[]
        | select(.space != $home)
        | select(.["can-move"] == true)
        | select(.["is-sticky"] != true)
        | select(.["is-native-fullscreen"] != true)
        | .app as $app
        | select(($owned | index($app)) == null)
        | .id
    '
end

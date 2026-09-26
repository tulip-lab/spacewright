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

function workspace_managed_window_ids_json --description "Return windows currently owned by their configured labeled workspace"
    argparse 'spaces-json=' -- $argv
    or return 1

    if not set -q _flag_spaces_json
        echo "usage: workspace_managed_window_ids_json --spaces-json <json>" >&2
        return 2
    end

    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        set windows_json '[]'
    end

    set -l config (spacewright_config_effective | string collect)
    or return 1

    printf "%s\n" "$config" | jq -c \
        --argjson spaces "$_flag_spaces_json" \
        --argjson windows "$windows_json" '
            . as $root
            | [
                $root.workspaces[]
                | . as $workspace
                | {
                    label: $workspace.label,
                    app_names: [
                        $workspace.windows[]?.app_key as $key
                        | $root.apps[$key].names[]?
                    ] | unique
                  }
              ] as $claims
            | [
                $windows[]
                | . as $window
                | ($spaces | first(.[] | select(.index == $window.space)) | .label // "") as $label
                | select(any($claims[]; .label == $label and (.app_names | index($window.app)) != null))
                | .id
              ]
        '
end

function workspace_sandbox_candidate_window_ids --description "Select movable windows not owned by their configured workspace"
    argparse 'spaces-json=' 'home-space=' -- $argv
    or return 1

    if not set -q _flag_spaces_json
        echo "usage: workspace_sandbox_candidate_window_ids --spaces-json <json> [--home-space <index>]" >&2
        return 2
    end

    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        set windows_json '[]'
    end
    set -l managed_ids (echo $windows_json | workspace_managed_window_ids_json --spaces-json "$_flag_spaces_json")
    or return 1

    echo $windows_json | ws_jq -r --argjson managed "$managed_ids" '
        .[]
        | select(.["can-move"] == true)
        | select(.["is-sticky"] != true)
        | select(.["is-native-fullscreen"] != true)
        | .id as $id
        | select(($managed | index($id)) == null)
        | .id
    '
end

function workspace_apply_sandbox --description "Collect unmanaged windows into a balanced mode Sandbox"
    argparse 'mode=' 'home-space=' 'display=' -- $argv
    or return 1

    if not set -q _flag_mode; or not contains -- $_flag_mode solo wide tall
        echo "usage: workspace_apply_sandbox --mode <solo|wide|tall> --home-space <index> --display <index>" >&2
        return 2
    end
    if not set -q _flag_home_space; or not set -q _flag_display
        echo "usage: workspace_apply_sandbox --mode <solo|wide|tall> --home-space <index> --display <index>" >&2
        return 2
    end

    set -l spaces_json (ws_query_spaces workspace_apply_sandbox initial_spaces)
    or return 1
    set -l windows_json (ws_query_windows workspace_apply_sandbox initial)
    or return 1
    set -l ids (echo $windows_json | workspace_sandbox_candidate_window_ids \
        --spaces-json "$spaces_json" \
        --home-space $_flag_home_space)
    or return 1

    if test (count $ids) -eq 0
        return 0
    end

    set -l label sandbox_$_flag_mode
    set -l target_space (find_or_create_labeled_space $label $_flag_display)
    if test -z "$target_space"
        return 1
    end

    prepare_labeled_space $target_space $label bsp
    or return 1
    ws_move_windows_to_space $target_space $ids
    or return 1
    ws_yabai -m space $target_space --layout bsp >/dev/null 2>&1
    or return 1
    ws_yabai -m space $target_space --balance >/dev/null 2>&1
    or return 1

    set windows_json (ws_query_windows workspace_apply_sandbox confirm)
    or return 1
    set -l ids_json (printf "%s\n" $ids | ws_jq -R 'tonumber' | ws_jq -s .)
    or return 1

    echo $windows_json | ws_jq -e \
        --argjson target $target_space \
        --argjson ids "$ids_json" '
            [$ids[] as $id | any(.[]; .id==$id and .space==$target)] | all
        ' >/dev/null
end

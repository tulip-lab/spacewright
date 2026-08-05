function workspace_cleanup_empty_spaces --description "Destroy live-empty Spaces except Home and one survivor per display"
    argparse 'home-uuid=' 'focus-uuid=' -- $argv
    or return 1

    set -l home_uuid ""
    if set -q _flag_home_uuid
        set home_uuid $_flag_home_uuid
    end

    set -l focus_uuid ""
    if set -q _flag_focus_uuid
        set focus_uuid $_flag_focus_uuid
    end

    set -l spaces_json (ws_query_spaces workspace_cleanup_empty_spaces spaces)
    or return 1
    set -l windows_json (ws_query_windows workspace_cleanup_empty_spaces windows)
    or return 1

    set -l candidates (echo $spaces_json | ws_jq -r \
        --arg home "$home_uuid" \
        --argjson windows "$windows_json" '
            def ordinary_count($space):
                [$windows[] | select(.space==$space.index and .["is-sticky"]!=true)] | length;

            group_by(.display)
            | map(
                . as $group
                | (
                    ([$group[] | select(.uuid==$home)] | first)
                    // ([$group[] | select(ordinary_count(.)>0)] | sort_by(.index) | first)
                    // ($group | sort_by(.index) | first)
                  ) as $survivor
                | [$group[]
                    | select(.uuid != $survivor.uuid)
                    | select(ordinary_count(.)==0)]
              )
            | add // []
            | sort_by(.index) | reverse | .[]
            | [.uuid, (.index|tostring), (.display|tostring)] | @tsv
        ')
    or return 1

    for candidate in $candidates
        set -l parts (string split \t -- "$candidate")
        set -l uuid $parts[1]
        set -l display $parts[3]

        if test -n "$focus_uuid" -a "$uuid" = "$focus_uuid"
            set -l safe_index (echo $spaces_json | ws_jq -r \
                --argjson display $display \
                --arg uuid "$uuid" \
                --arg home "$home_uuid" \
                --argjson windows "$windows_json" '
                    def ordinary_count($space):
                        [$windows[] | select(.space==$space.index and .["is-sticky"]!=true)] | length;

                    first(.[]
                        | select(.display==$display and .uuid!=$uuid)
                        | select(.uuid==$home or ordinary_count(.)>0)
                        | .index)
                    // first(.[] | select(.display==$display and .uuid!=$uuid) | .index)
                    // empty
                ')
            if test -z "$safe_index"
                return 1
            end
            ws_focus_space $safe_index >/dev/null 2>&1
            or return 1
        end

        ws_yabai -m space $uuid --destroy >/dev/null 2>&1
        or return 1
    end
end

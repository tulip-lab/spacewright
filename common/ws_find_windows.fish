function ws_find_windows --description "Find matching non-minimized window ids from yabai window JSON"
    argparse 'space=' 'not-space=' 'app-regex=' 'exclude-title=' visible nonempty-title movable -- $argv
    or return 1

    set -l app $argv[1]
    if test -z "$app" -a -z "$_flag_app_regex"
        return 1
    end

    set -l space "$_flag_space"
    set -l not_space "$_flag_not_space"
    set -l app_regex "$_flag_app_regex"
    set -l exclude_title "$_flag_exclude_title"
    set -l visible 0
    set -l nonempty_title 0
    set -l movable 0

    if set -q _flag_visible
        set visible 1
    end

    if set -q _flag_nonempty_title
        set nonempty_title 1
    end

    if set -q _flag_movable
        set movable 1
    end

    set -l exclude_title_json '[]'
    set -l exclude_title_values
    for title in $exclude_title
        if test -n "$title"
            set -a exclude_title_values "$title"
        end
    end

    if test (count $exclude_title_values) -gt 0
        set exclude_title_json (printf '%s\n' $exclude_title_values | ws_jq -R . | ws_jq -s .)
    end

    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        return 1
    end

    printf '%s\n' "$windows_json" | ws_jq -r \
        --arg app "$app" \
        --arg app_regex "$app_regex" \
        --arg space "$space" \
        --arg not_space "$not_space" \
        --arg visible "$visible" \
        --arg nonempty_title "$nonempty_title" \
        --arg movable "$movable" \
        --argjson exclude_title "$exclude_title_json" '
        .[]
        | select(
            if $app_regex != "" then
                (.app | test($app_regex))
            else
                .app==$app
            end
        )
        | select(.["is-minimized"]==false)
        | select(($visible!="1") or (.["is-visible"]==true))
        | select(($nonempty_title!="1") or (.title != null and .title != ""))
        | select(($movable!="1") or (.["can-move"]==true))
        | . as $window
        | select(
            ($exclude_title | length == 0) or all($exclude_title[];
                . as $needle
                | (($window.title // "") | ascii_downcase | contains($needle | ascii_downcase) | not)
            )
        )
        | select(($space=="") or (.space==($space | tonumber)))
        | select(($not_space=="") or (.space!=($not_space | tonumber)))
        | .id
    '
end

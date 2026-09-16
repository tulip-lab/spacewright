function ws_find_windows --description "Find matching non-minimized window ids from yabai window JSON"
    argparse 'space=' 'not-space=' 'app-regex=' 'exclude-title=' visible nonempty-title movable not-native-fullscreen -- $argv
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
    set -l not_native_fullscreen 0

    if set -q _flag_visible
        set visible 1
    end

    if set -q _flag_nonempty_title
        set nonempty_title 1
    end

    if set -q _flag_movable
        set movable 1
    end

    if set -q _flag_not_native_fullscreen
        set not_native_fullscreen 1
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
        --arg not_native_fullscreen "$not_native_fullscreen" \
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
        | select(($not_native_fullscreen!="1") or (.["is-native-fullscreen"]!=true))
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

function ws_find_window --description "Find the first matching non-minimized window id from yabai window JSON"
    set -l windows_json
    read -lz windows_json
    if test -z "$windows_json"
        return 1
    end

    set -l candidates (printf '%s\n' "$windows_json" | ws_find_windows $argv)
    or return 1

    set -l bad_window_ttl "$WORKSPACE_BAD_WINDOW_TTL_SECONDS"
    if test -z "$bad_window_ttl"
        set bad_window_ttl 600
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad

    for window_id in $candidates
        set -l bad_window_file $bad_window_dir/$window_id

        if test -f "$bad_window_file"
            set -l now (date +%s)
            set -l bad_at (cat "$bad_window_file" 2>/dev/null)

            if string match -qr '^[0-9]+$' -- "$bad_at"
                set -l age (math $now - $bad_at)

                if test "$age" -lt "$bad_window_ttl"
                    continue
                end
            end
        end

        echo $window_id
        return 0
    end
end

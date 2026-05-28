function ws_focus_display --description "Focus a display only when it is not already focused"
    if test (count $argv) -lt 1
        echo "usage: ws_focus_display <display_index>"
        return 1
    end

    set -l target_display $argv[1]
    set -l current_display_json (ws_yabai -m query --displays --display 2>/dev/null)
    if test $status -ne 0 -o -z "$current_display_json"
        return 1
    end

    set -l current_display (echo $current_display_json | ws_jq -r '.index')

    if test -z "$current_display"
        return 1
    end

    if test "$current_display" = "$target_display"
        return 0
    end

    ws_yabai -m display --focus $target_display >/dev/null 2>&1
end

function ws_focus_space --description "Focus a space only when it is not already focused"
    if test (count $argv) -lt 1
        echo "usage: ws_focus_space <space_index>"
        return 1
    end

    set -l target_space $argv[1]
    set -l current_space_json (ws_yabai -m query --spaces --space 2>/dev/null)
    if test $status -ne 0 -o -z "$current_space_json"
        return 1
    end

    set -l current_space (echo $current_space_json | ws_jq -r '.index')

    if test -z "$current_space"
        return 1
    end

    if test "$current_space" = "$target_space"
        return 0
    end

    ws_yabai -m space --focus $target_space >/dev/null 2>&1
end

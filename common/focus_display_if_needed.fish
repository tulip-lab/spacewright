function focus_display_if_needed
    if test (count $argv) -lt 1
        echo "usage: focus_display_if_needed <display_index>"
        return 1
    end

    set -l target_display $argv[1]
    set -l current_display (ws_yabai -m query --displays --display 2>/dev/null | jq -r '.index')

    if test -z "$current_display"
        return 1
    end

    if test "$current_display" = "$target_display"
        return 0
    end

    ws_yabai -m display --focus $target_display >/dev/null 2>&1
end

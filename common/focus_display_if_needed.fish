function focus_display_if_needed
    if test (count $argv) -lt 1
        echo "usage: focus_display_if_needed <display_index>"
        return 1
    end

    set target_display $argv[1]
    set current_display (yabai -m query --displays | jq -r '.[] | select(.["has-focus"]==true) | .index' | head -n 1)

    if test "$current_display" != "$target_display"
        yabai -m display --focus $target_display
    end
end
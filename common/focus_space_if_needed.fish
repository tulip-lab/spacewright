function focus_space_if_needed
    if test (count $argv) -lt 1
        echo "usage: focus_space_if_needed <space_index>"
        return 1
    end

    set target_space $argv[1]
    set current_space (yabai -m query --spaces | jq -r '.[] | select(.["has-focus"]==true) | .index' | head -n 1)

    if test "$current_space" != "$target_space"
        yabai -m space --focus $target_space
    end
end
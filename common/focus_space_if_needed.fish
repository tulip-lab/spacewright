function focus_space_if_needed
    if test (count $argv) -lt 1
        echo "usage: focus_space_if_needed <space_index>"
        return 1
    end

    set -l target_space $argv[1]
    set -l current_space (yabai -m query --spaces --space 2>/dev/null | jq -r '.index')

    if test -z "$current_space"
        return 1
    end

    if test "$current_space" = "$target_space"
        return 0
    end

    yabai -m space --focus $target_space 2>/dev/null
end
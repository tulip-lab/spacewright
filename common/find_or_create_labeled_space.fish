function find_or_create_labeled_space --description "Find an existing labeled space or create a new one on target display"
    set -l label $argv[1]
    set -l target_display $argv[2]

    if test -z "$label"
        return 1
    end

    if test -z "$target_display"
        set target_display 1
    end

    set -l existing_space (yabai -m query --spaces | jq -r --arg label "$label" '.[] | select(.label==$label) | .index' | head -n 1)

    if test -n "$existing_space"
        echo $existing_space
        return 0
    end

    focus_display_if_needed $target_display
    sleep 0.4

    yabai -m space --create
    sleep 0.8

    set -l new_space (yabai -m query --spaces | jq -r --argjson display "$target_display" '.[] | select(.display==$display and .label=="") | .index' | tail -n 1)

    if test -n "$new_space"
        echo $new_space
        return 0
    end

    return 1
end
function prepare_labeled_space --description "Normalize labeled space state"
    set -l target_space $argv[1]
    set -l label $argv[2]
    set -l layout $argv[3]

    if test -z "$target_space"
        return 1
    end

    if test -z "$layout"
        set layout float
    end

    if test -n "$label"
        yabai -m space $target_space --label $label
    end

    yabai -m space $target_space --layout $layout
end
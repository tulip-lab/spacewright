function workspace_prepare_labeled_space --description "Prepare and focus a labeled workspace space"
    set -l label $argv[1]
    set -l target_display $argv[2]
    set -l layout $argv[3]
    set -l cleanup_commands $argv[4..-1]

    if test -z "$label" -o -z "$target_display"
        echo "usage: workspace_prepare_labeled_space <label> <target-display> [layout] [cleanup-command ...]" >&2
        return 2
    end

    if test -z "$layout"
        set layout float
    end

    set -l target_space (find_or_create_labeled_space $label $target_display)
    if test -z "$target_space"
        return 1
    end

    workspace_focus_labeled_space $label $target_space $target_display $layout $cleanup_commands
    or return 1

    echo $target_space
end

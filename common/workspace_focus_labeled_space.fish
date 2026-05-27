function workspace_focus_labeled_space --description "Normalize and focus an existing labeled workspace space"
    set -l label $argv[1]
    set -l target_space $argv[2]
    set -l target_display $argv[3]
    set -l layout $argv[4]
    set -l cleanup_commands $argv[5..-1]

    if test -z "$label" -o -z "$target_space" -o -z "$target_display"
        echo "usage: workspace_focus_labeled_space <label> <target-space> <target-display> [layout] [cleanup-command ...]" >&2
        return 2
    end

    if test -z "$layout"
        set layout float
    end

    prepare_labeled_space $target_space $label $layout

    ws_focus_display $target_display
    sleep 0.15

    for cleanup_command in $cleanup_commands
        if functions -q $cleanup_command
            $cleanup_command
        else
            echo "[WARN] workspace_focus_labeled_space: cleanup command not found: $cleanup_command" >&2
            return 1
        end
    end

    ws_focus_space $target_space
    sleep 0.15
end

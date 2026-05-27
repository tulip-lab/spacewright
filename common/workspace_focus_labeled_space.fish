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

    workspace_run_cleanup_specs $cleanup_commands
    or return 1

    ws_focus_space $target_space
    sleep 0.15
end

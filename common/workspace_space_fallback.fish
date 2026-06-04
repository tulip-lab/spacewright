function workspace_focus_space_fallback --description "Move, normalize and focus an app-owned fallback space"
    argparse \
        'label=' \
        'caller=' \
        'space=' \
        'source-display=' \
        'target-display=' \
        'layout=' \
        'phase=' \
        -- $argv
    or return 1

    if not set -q _flag_label; or not set -q _flag_space; or not set -q _flag_source_display; or not set -q _flag_target_display
        echo "usage: workspace_focus_space_fallback --label <label> --space <space> --source-display <display> --target-display <display> [--caller <name>] [--layout <layout>] [--phase <debug-phase>] [cleanup-command ...]" >&2
        return 2
    end

    set -l caller $_flag_label
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l layout float
    if set -q _flag_layout
        set layout $_flag_layout
    end

    set -l phase space-fallback
    if set -q _flag_phase
        set phase $_flag_phase
    end

    set -l target_space $_flag_space
    set -l cleanup_commands $argv

    set -l initial_phase "$phase"-initial
    set -l spaces_json_fallback (ws_query_spaces $caller $initial_phase)
    if test $status -ne 0 -o -z "$spaces_json_fallback"
        return 1
    end

    set -l target_space_uuid (echo $spaces_json_fallback | ws_jq -r --argjson s $target_space '
        first(.[] | select(.index==$s) | .uuid) // empty
    ')

    if test -z "$target_space_uuid"
        return 1
    end

    if test "$_flag_source_display" != "$_flag_target_display"
        workspace_debug_step $caller "$phase-move-space" "$target_space" display=$_flag_target_display
        ws_yabai -m space $target_space --display $_flag_target_display >/dev/null 2>&1
        sleep 0.8

        set -l after_move_phase "$phase"-after-display-move
        set spaces_json_fallback (ws_query_spaces $caller $after_move_phase)
        if test $status -ne 0 -o -z "$spaces_json_fallback"
            return 1
        end

        set target_space (echo $spaces_json_fallback | ws_jq -r --arg uuid "$target_space_uuid" '
            first(.[] | select(.uuid==$uuid) | .index) // empty
        ')

        if test -z "$target_space"
            return 1
        end
    end

    workspace_focus_labeled_space $_flag_label $target_space $_flag_target_display $layout $cleanup_commands
    or return 1

    echo $target_space
end

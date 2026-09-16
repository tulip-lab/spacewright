function ws_move_windows_to_space --description "Move multiple windows to a target space and refocus only when work was attempted"
    if test (count $argv) -lt 1
        return 1
    end

    set -l target_space $argv[1]
    set -e argv[1]

    if test -z "$target_space"
        return 1
    end

    if test (count $argv) -eq 0
        return 0
    end

    set -l attempted 0

    for window_id in $argv
        if test -n "$window_id" -a "$window_id" != "null"
            set attempted 1
            ws_window $window_id --space $target_space
        end
    end

    if test "$attempted" -eq 0
        return 0
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15
end

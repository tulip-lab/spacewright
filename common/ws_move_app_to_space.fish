function ws_move_app_to_space --description "Move an app window to a target space"
    argparse 'app-regex=' 'exclude-title=' visible nonempty-title -- $argv
    or return 1

    set -l target_space $argv[1]
    set -l window_id $argv[3]

    if test -z "$target_space"
        return 1
    end

    ws_move_windows_to_space $target_space $window_id
end

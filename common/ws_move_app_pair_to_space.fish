function ws_move_app_pair_to_space --description "Move a primary/helper app pair to a target space"
    argparse primary-visible helper-visible -- $argv
    or return 1

    set -l target_space $argv[1]
    set -l primary_window $argv[3]
    set -l helper_window $argv[5]

    if test -z "$target_space"
        return 1
    end

    ws_move_windows_to_space $target_space $primary_window $helper_window
end

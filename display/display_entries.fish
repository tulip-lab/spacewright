function display_apply_profile_mode --description "Apply a display profile, reload workspace functions, and verify mode"
    set -l profile_command $argv[1]
    set -l mode $argv[2]

    if test -z "$profile_command" -o -z "$mode"
        echo "usage: display_apply_profile_mode <profile-command> <solo|wide|tall>" >&2
        return 2
    end

    $profile_command
    or return $status

    display_reload
    or return $status

    work_reload
    or return $status

    display_verify_mode $mode
end

function display_apply_solo --description "Apply solo primary-display layout and reload display/workspace functions"
    display_apply_profile_mode ~/.config/displayprofiles/display-solo-primary.fish solo
end

function display_apply_wide_left --description "Apply wide-left display layout and reload display/workspace functions"
    display_apply_profile_mode ~/.config/displayprofiles/display-primary-plus-wide-left.fish wide
end

function display_apply_tall_left --description "Apply tall-left display layout and reload display/workspace functions"
    display_apply_profile_mode ~/.config/displayprofiles/display-primary-plus-tall-left.fish tall
end

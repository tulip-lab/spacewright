function display_apply_solo --description "Apply solo primary-display layout and reload display/workspace functions"
    ~/.config/displayprofiles/display-solo-primary.fish
    or return $status

    display_reload
    or return $status

    work_reload
    or return $status

    display_verify_mode solo
end

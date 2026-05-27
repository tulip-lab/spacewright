function display_apply_wide_left --description "Apply wide-left display layout and reload display/workspace functions"
    ~/.config/displayprofiles/display-primary-plus-wide-left.fish
    or return $status

    display_reload
    or return $status

    work_reload
    or return $status

    display_verify_mode wide
end

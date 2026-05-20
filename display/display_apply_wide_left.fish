function display_apply_wide_left --description "Apply wide-left display layout and reload display/workspace functions"
    display_wide_left
    or return $status

    display_reload
    or return $status

    work_reload
    or return $status

    display_verify_mode wide
end

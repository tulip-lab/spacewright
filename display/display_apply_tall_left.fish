function display_apply_tall_left --description "Apply tall-left display layout and reload display/workspace functions"
    display_tall_left
    or return $status

    display_reload
    or return $status

    work_reload
    or return $status

    display_verify_mode tall
end

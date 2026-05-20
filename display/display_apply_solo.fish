function display_apply_solo --description "Apply solo internal-display layout and reload display/workspace functions"
    display_solo
    or return $status

    display_reload
    or return $status

    work_reload
    or return $status

    display_verify_mode solo
end

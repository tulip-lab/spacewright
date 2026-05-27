function work_wide
    set -l failed 0

    workspace_run_step "coding wide" coding_wide
    or set failed 1

    workspace_run_step "coding control" coding_control
    or set failed 1

    workspace_run_step "research wide" research_wide
    or set failed 1

    workspace_run_step "office wide" office_wide
    or set failed 1

    workspace_run_step "GTD wide" gtd_wide
    or set failed 1

    workspace_run_step "GTD chat" gtd_chat
    or set failed 1

    workspace_run_step "GTD calendar" gtd_calendar
    or set failed 1

    return $failed
end

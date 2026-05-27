function work_tall
    set -l failed 0

    workspace_run_step "coding tall" coding_tall
    or set failed 1

    workspace_run_step "coding control" coding_control
    or set failed 1

    workspace_run_step "research tall" research_tall
    or set failed 1

    workspace_run_step "office tall" office_tall
    or set failed 1

    workspace_run_step "GTD tall" gtd_tall
    or set failed 1

    workspace_run_step "GTD chat" gtd_chat
    or set failed 1

    workspace_run_step "GTD calendar" gtd_calendar
    or set failed 1

    return $failed
end

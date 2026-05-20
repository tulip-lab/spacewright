function work_wide
    set -l failed 0

    workspace_run_step "coding wide all" coding_wide_all
    or set failed 1

    workspace_run_step "research wide" research_wide
    or set failed 1

    workspace_run_step "GTD wide all" gtd_wide_all
    or set failed 1
#    office_wide

    return $failed
end

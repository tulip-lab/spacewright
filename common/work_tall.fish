function work_tall
    set -l failed 0

    workspace_run_step "coding tall all" coding_tall_all
    or set failed 1

    workspace_run_step "research tall" research_tall
    or set failed 1

    workspace_run_step "office tall" office_tall
    or set failed 1

    workspace_run_step "GTD tall all" gtd_tall_all
    or set failed 1

    return $failed
end

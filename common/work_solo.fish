function work_solo --description "Arrange solo internal-display workspaces"
    set -l failed 0

    workspace_run_step "coding solo" coding_solo
    or set failed 1

    workspace_run_step "research solo" research_solo
    or set failed 1

    workspace_run_step "GTD solo all" gtd_solo_all
    or set failed 1

    return $failed
end

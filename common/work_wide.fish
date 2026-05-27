function work_wide
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=work_wide\n"
        printf "commands=%s\n" coding_wide coding_control research_wide office_wide gtd_wide gtd_chat gtd_calendar
        return 0
    end

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

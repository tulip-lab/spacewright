function work_tall
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=work_tall\n"
        printf "commands=%s\n" coding_tall coding_control research_tall office_tall gtd_tall gtd_chat gtd_calendar
        return 0
    end

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

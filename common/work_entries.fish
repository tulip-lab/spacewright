function work_solo --description "Arrange solo primary-display workspaces"
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=work_solo\n"
        printf "commands=%s\n" (workspace_top_level_commands work_solo)
        return 0
    end

    set -l failed 0

    workspace_run_step "coding solo" coding_solo
    or set failed 1

    workspace_run_step "research solo" research_solo
    or set failed 1

    workspace_run_step "GTD solo all" gtd_solo_all
    or set failed 1

    return $failed
end

function work_wide
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=work_wide\n"
        printf "commands=%s\n" (workspace_top_level_commands work_wide)
        return 0
    end

    set -l failed 0

    workspace_run_step "coding wide" coding_wide
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

    workspace_run_step "coding control" coding_control
    or set failed 1

    return $failed
end

function work_tall
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=work_tall\n"
        printf "commands=%s\n" (workspace_top_level_commands work_tall)
        return 0
    end

    set -l failed 0

    workspace_run_step "coding tall" coding_tall
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

    workspace_run_step "coding control" coding_control
    or set failed 1

    return $failed
end

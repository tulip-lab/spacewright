function work_solo --description "Arrange solo primary-display workspaces"
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=work_solo\n"
        printf "commands=%s\n" coding_solo research_solo gtd_solo_all
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

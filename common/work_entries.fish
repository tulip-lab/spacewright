function __work_solo_body --description "Arrange solo primary-display workspaces"
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

    workspace_run_step "primary fixed-space separation" workspace_reconcile_primary_fixed_spaces
    or set failed 1

    return $failed
end

function __work_wide_body
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=work_wide\n"
        printf "commands=%s\n" (workspace_top_level_commands work_wide)
        return 0
    end

    set -l failed 0

    workspace_run_step "research wide" research_wide
    or set failed 1

    workspace_run_step "office wide" office_wide
    or set failed 1

    workspace_run_step "GTD support wide" gtd_support_wide
    or set failed 1

    workspace_run_step "GTD review wide" gtd_review_wide
    or set failed 1

    workspace_run_step "coding editor wide" coding_editor_wide
    or set failed 1

    workspace_run_step "GTD mail wide" gtd_mail_wide
    or set failed 1

    workspace_run_step "GTD meeting wide" gtd_meeting_wide
    or set failed 1

    workspace_run_step "GTD chat" gtd_chat
    or set failed 1

    workspace_run_step "GTD calendar" gtd_calendar
    or set failed 1

    workspace_run_step "coding control" coding_control
    or set failed 1

    workspace_run_step "primary fixed-space separation" workspace_reconcile_primary_fixed_spaces
    or set failed 1

    return $failed
end

function __work_tall_body
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=work_tall\n"
        printf "commands=%s\n" (workspace_top_level_commands work_tall)
        return 0
    end

    set -l failed 0

    workspace_run_step "research tall" research_tall
    or set failed 1

    workspace_run_step "office tall" office_tall
    or set failed 1

    workspace_run_step "GTD support tall" gtd_support_tall
    or set failed 1

    workspace_run_step "GTD review tall" gtd_review_tall
    or set failed 1

    workspace_run_step "coding editor tall" coding_editor_tall
    or set failed 1

    workspace_run_step "GTD mail tall" gtd_mail_tall
    or set failed 1

    workspace_run_step "GTD meeting tall" gtd_meeting_tall
    or set failed 1

    workspace_run_step "GTD chat" gtd_chat
    or set failed 1

    workspace_run_step "GTD calendar" gtd_calendar
    or set failed 1

    workspace_run_step "coding control" coding_control
    or set failed 1

    workspace_run_step "primary fixed-space separation" workspace_reconcile_primary_fixed_spaces
    or set failed 1

    return $failed
end

function work_solo --description "Arrange solo primary-display workspaces"
    workspace_run_finalized_entry --mode solo --command __work_solo_body -- $argv
end

function work_wide --description "Arrange wide external-display workspaces"
    workspace_run_finalized_entry --mode wide --command __work_wide_body -- $argv
end

function work_tall --description "Arrange tall external-display workspaces"
    workspace_run_finalized_entry --mode tall --command __work_tall_body -- $argv
end

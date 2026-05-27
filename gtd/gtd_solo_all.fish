function gtd_solo_all --description "Arrange GTD solo workspaces including internal fixed workspaces"
    set -l failed 0

    workspace_run_step "cleanup GTD wide spaces" workspace_cleanup_mode_spaces gtd wide
    or set failed 1

    workspace_run_step "cleanup GTD tall spaces" workspace_cleanup_mode_spaces gtd tall
    or set failed 1

    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    workspace_run_step "GTD support solo" gtd_support_solo
    or set failed 1

    workspace_run_step "GTD mail solo" gtd_mail_solo
    or set failed 1

    workspace_run_step "GTD meeting solo" gtd_meeting_solo
    or set failed 1

    workspace_run_step "GTD review solo" gtd_review_solo
    or set failed 1

    workspace_run_step "GTD chat internal" gtd_chat
    or set failed 1

    workspace_run_step "GTD calendar internal" gtd_calendar
    or set failed 1

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    workspace_run_step "final cleanup GTD wide spaces" workspace_cleanup_mode_spaces gtd wide
    or set failed 1

    workspace_run_step "final cleanup GTD tall spaces" workspace_cleanup_mode_spaces gtd tall
    or set failed 1

    return $failed
end

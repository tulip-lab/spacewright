function gtd_solo_all --description "Arrange GTD solo workspaces including internal fixed workspaces"
    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces

    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    gtd_support_solo
    gtd_review_solo
    gtd_mail_solo
    gtd_meeting_solo

    gtd_chat
    gtd_calendar

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    gtd_cleanup_wide_spaces
    gtd_cleanup_tall_spaces
end

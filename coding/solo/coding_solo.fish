function coding_solo --description "Arrange coding solo workspaces and internal coding controls"
    coding_cleanup_wide_spaces
    coding_cleanup_tall_spaces

    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    coding_editor_solo
    coding_control

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    coding_cleanup_wide_spaces
    coding_cleanup_tall_spaces
end

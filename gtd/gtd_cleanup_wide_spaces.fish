function gtd_cleanup_wide_spaces --description "Destroy empty labeled GTD wide spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Remove empty GTD wide workspaces that are no longer in use.
    #
    # Why this function still exists:
    #   This function is intentionally different from
    #   `cleanup_unlabeled_empty_spaces`.
    #
    #   - `cleanup_unlabeled_empty_spaces` only removes empty spaces that have
    #     no label.
    #   - `gtd_cleanup_wide_spaces` removes empty GTD workspaces that *do* have
    #     labels, specifically labels matching the wide-mode GTD pattern.
    #
    # This is important when switching between GTD tall mode and GTD wide mode:
    #   after windows are moved away, previously used GTD wide spaces may become
    #   empty, but they still retain labels such as:
    #     - gtd_mail_wide
    #     - gtd_meeting_wide
    #     - gtd_support_wide
    #     - gtd_review_wide
    #
    # Without this cleanup step, empty labeled GTD wide spaces would remain in
    # the Space list and accumulate over time.
    #
    # Matching rule:
    #   Destroy spaces whose labels match:
    #       ^gtd_.*_wide$
    #
    # Safety rule:
    #   Only spaces with zero windows are destroyed.
    #
    # Order:
    #   Spaces are destroyed in descending index order so that removing one
    #   space does not interfere with subsequent indices still waiting to be
    #   processed.
    # -------------------------------------------------------------------------

    set -l candidates (yabai -m query --spaces | jq -r '
        [.[]
        | select(.label | test("^gtd_.*_wide$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty GTD wide space: $s"
        yabai -m space $s --destroy
    end
end
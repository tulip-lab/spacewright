function gtd_cleanup_tall_spaces --description "Destroy empty labeled GTD tall spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Remove empty GTD tall workspaces that are no longer in use.
    #
    # Why this function still exists:
    #   This function is intentionally different from
    #   `cleanup_unlabeled_empty_spaces`.
    #
    #   - `cleanup_unlabeled_empty_spaces` only removes empty spaces that have
    #     no label.
    #   - `gtd_cleanup_tall_spaces` removes empty GTD workspaces that *do* have
    #     labels, specifically labels matching the tall-mode GTD pattern.
    #
    # This is important when switching between GTD wide mode and GTD tall mode:
    #   after windows are moved away, previously used GTD tall spaces may become
    #   empty, but they still retain labels such as:
    #     - gtd_mail_tall
    #     - gtd_meeting_tall
    #     - gtd_support_tall
    #     - gtd_review_tall
    #
    # Without this cleanup step, empty labeled GTD tall spaces would remain in
    # the Space list and accumulate over time.
    #
    # Matching rule:
    #   Destroy spaces whose labels match:
    #       ^gtd_.*_tall$
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
        | select(.label | test("^gtd_.*_tall$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty GTD tall space: $s"
        yabai -m space $s --destroy
    end
end
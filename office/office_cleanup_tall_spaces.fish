function office_cleanup_tall_spaces --description "Destroy empty labeled office tall spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Remove empty office tall workspaces that are no longer in use.
    #
    # Why this function still exists:
    #   This function is intentionally different from
    #   `cleanup_unlabeled_empty_spaces`.
    #
    #   - `cleanup_unlabeled_empty_spaces` only removes empty spaces that have
    #     no label.
    #   - `office_cleanup_tall_spaces` removes empty office workspaces that do
    #     have labels, specifically labels matching the tall-mode office pattern.
    #
    # This is important when switching between office wide mode and office tall
    # mode. After windows are moved away, previously used office tall spaces may
    # become empty, but they still retain labels such as:
    #   - office_writing_tall
    #   - office_slides_tall
    #
    # Matching rule:
    #   Destroy spaces whose labels match:
    #       ^office_.*_tall$
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
        | select(.label | test("^office_.*_tall$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Office tall space: $s"
        yabai -m space $s --destroy
    end
end
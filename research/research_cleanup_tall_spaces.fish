function research_cleanup_tall_spaces --description "Destroy empty labeled research tall spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Remove empty research tall workspaces that are no longer in use.
    #
    # Why this function still exists:
    #   This function is intentionally different from
    #   `cleanup_unlabeled_empty_spaces`.
    #
    #   - `cleanup_unlabeled_empty_spaces` only removes empty spaces that have
    #     no label.
    #   - `research_cleanup_tall_spaces` removes empty research workspaces that
    #     do have labels, specifically labels matching the tall-mode research
    #     pattern.
    #
    # This is important when switching between research wide mode and research
    # tall mode. After windows are moved away, previously used research tall
    # spaces may become empty, but they still retain labels such as:
    #   - research_tall
    #
    # Matching rule:
    #   Destroy spaces whose labels match:
    #       ^research.*_tall$
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
        | select(.label | test("^research.*_tall$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Research tall space: $s"
        yabai -m space $s --destroy
    end
end
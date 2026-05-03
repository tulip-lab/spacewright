function research_cleanup_wide_spaces --description "Destroy empty labeled research wide spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Remove empty research wide workspaces that are no longer in use.
    #
    # Why this function still exists:
    #   This function is intentionally different from
    #   `cleanup_unlabeled_empty_spaces`.
    #
    #   - `cleanup_unlabeled_empty_spaces` only removes empty spaces that have
    #     no label.
    #   - `research_cleanup_wide_spaces` removes empty research workspaces that
    #     do have labels, specifically labels matching the wide-mode research
    #     pattern.
    #
    # This is important when switching between research tall mode and research
    # wide mode. After windows are moved away, previously used research wide
    # spaces may become empty, but they still retain labels such as:
    #   - research_wide
    #
    # Matching rule:
    #   Destroy spaces whose labels match:
    #       ^research.*_wide$
    #   The explicit equality check for `research_wide` is retained for
    #   compatibility with the current single-workspace naming style.
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
        | select((.label | test("^research.*_wide$")) or (.label == "research_wide"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Research wide space: $s"
        yabai -m space $s --destroy
    end
end
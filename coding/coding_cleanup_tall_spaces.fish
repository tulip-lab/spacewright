function coding_cleanup_tall_spaces --description "Destroy empty labeled coding tall spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Remove empty coding tall workspaces that are no longer in use.
    #
    # Why this function still exists:
    #   This function is intentionally different from
    #   `cleanup_unlabeled_empty_spaces`.
    #
    #   - `cleanup_unlabeled_empty_spaces` only removes empty spaces that have
    #     no label.
    #   - `coding_cleanup_tall_spaces` removes empty coding workspaces that do
    #     have labels, specifically labels matching the tall-mode coding pattern.
    #
    # This is important when switching between coding wide mode and coding tall
    # mode. After windows are moved away, previously used coding tall spaces may
    # become empty, but they still retain labels such as:
    #   - coding_editor_tall
    #
    # Matching rule:
    #   Destroy spaces whose labels match:
    #       ^coding_.*_tall$
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
        | select(.label | test("^coding_.*_tall$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Coding tall space: $s"
        yabai -m space $s --destroy
    end
end
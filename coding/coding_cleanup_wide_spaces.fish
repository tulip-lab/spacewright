function coding_cleanup_wide_spaces --description "Destroy empty labeled coding wide spaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Remove empty coding wide workspaces that are no longer in use.
    #
    # Why this function still exists:
    #   This function is intentionally different from
    #   `cleanup_unlabeled_empty_spaces`.
    #
    #   - `cleanup_unlabeled_empty_spaces` only removes empty spaces that have
    #     no label.
    #   - `coding_cleanup_wide_spaces` removes empty coding workspaces that do
    #     have labels, specifically labels matching the wide-mode coding pattern.
    #
    # This is important when switching between coding tall mode and coding wide
    # mode. After windows are moved away, previously used coding wide spaces may
    # become empty, but they still retain labels such as:
    #   - coding_editor_wide
    #
    # Matching rule:
    #   Destroy spaces whose labels match:
    #       ^coding_.*_wide$
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
        | select(.label | test("^coding_.*_wide$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Coding wide space: $s"
        yabai -m space $s --destroy
    end
end
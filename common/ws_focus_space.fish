function ws_focus_space --description "Workspace wrapper for focusing a space only when needed"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Provide a workspace-layer wrapper around the existing
    #   `focus_space_if_needed` helper so workspace functions can use a
    #   consistent naming convention.
    #
    # Why this wrapper exists:
    #   The project already has `focus_space_if_needed`, which is functionally
    #   correct. This wrapper does not change that logic. It exists so
    #   workspace functions can read more consistently when used together with:
    #     - resolve_target_display
    #     - find_or_create_labeled_space
    #     - prepare_labeled_space
    #     - cleanup_unlabeled_empty_spaces
    #     - ws_focus_display
    #
    # Usage:
    #   ws_focus_space <space_index>
    #
    # Arguments:
    #   argv[1] -> target space index
    #
    # Notes:
    #   This is intentionally a thin wrapper. The actual space focus logic
    #   remains centralized in `focus_space_if_needed`.
    # -------------------------------------------------------------------------

    if test (count $argv) -lt 1
        return 1
    end

    focus_space_if_needed $argv[1]
end
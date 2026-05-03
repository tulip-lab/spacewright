function ws_focus_display --description "Workspace wrapper for focusing a display only when needed"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Provide a workspace-layer wrapper around the existing
    #   `focus_display_if_needed` helper so workspace functions can use a
    #   consistent naming convention.
    #
    # Why this wrapper exists:
    #   The project already has `focus_display_if_needed`, which is functionally
    #   correct. This wrapper does not replace its behavior. Instead, it gives
    #   workspace orchestration code a cleaner and more uniform call pattern
    #   alongside:
    #     - resolve_target_display
    #     - find_or_create_labeled_space
    #     - prepare_labeled_space
    #     - cleanup_unlabeled_empty_spaces
    #     - ws_focus_space
    #
    # Usage:
    #   ws_focus_display <display_index>
    #
    # Arguments:
    #   argv[1] -> target display index
    #
    # Notes:
    #   This is intentionally a thin wrapper. The actual display focus logic
    #   remains centralized in `focus_display_if_needed`.
    # -------------------------------------------------------------------------

    if test (count $argv) -lt 1
        return 1
    end

    focus_display_if_needed $argv[1]
end
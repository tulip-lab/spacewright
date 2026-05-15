function gtd_review_wide --description "Collect review-related windows onto the wide GTD review workspace and apply the standard review layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_review_wide
    #
    # Purpose:
    #   Move review-related applications to the GTD review workspace in wide
    #   mode and place them into a stable review layout.
    #
    # Target display:
    #   Prefer an external display.
    #   Fall back to the internal display if no external display is available.
    #
    # Managed apps:
    #   - Finder
    #   - Preview
    #   - ChatGPT
    #   - Notes
    #
    # Window selection rules:
    #   - Preview:
    #       Required primary window. If no non-minimized Preview window exists,
    #       the workspace is not created.
    #   - Notes:
    #       Prefer a non-minimized window whose title is not empty.
    #       If none is found, fall back to any non-minimized Notes window.
    #   - Finder / ChatGPT:
    #       Use the first non-minimized window if available.
    #
    # Layout:
    #   - Finder  -> left 1/4
    #   - Preview -> middle 3/8
    #   - ChatGPT -> right upper 3/8
    #   - Notes   -> right lower 3/8
    #
    # Notes:
    #   - Before entering GTD review wide mode, empty GTD tall spaces are
    #     cleaned.
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    # -------------------------------------------------------------------------
    # 1. Cleanup GTD tall spaces before entering wide mode
    # -------------------------------------------------------------------------
    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces

    set -l label gtd_review_wide

    # -------------------------------------------------------------------------
    # 2. Find Preview first; if not found, do not create the workspace
    # -------------------------------------------------------------------------
    set -l windows_json (yabai -m query --windows)

    set -l preview (echo $windows_json | ws_find_window "Preview")

    if test -z "$preview"
        destroy_empty_labeled_space $label

        return 0
    end

    # -------------------------------------------------------------------------
    # 3. Resolve target display
    #    Prefer an external display; if none exists, fall back to internal.
    # -------------------------------------------------------------------------
    set -l target_display (resolve_external_display)

    # -------------------------------------------------------------------------
    # 4. Find or create target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    # -------------------------------------------------------------------------
    # 5. Normalize target space state
    # -------------------------------------------------------------------------
    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 6. First-pass window capture
    # -------------------------------------------------------------------------
    set -l finder (echo $windows_json | ws_find_window "Finder")

    set -l chatgpt (echo $windows_json | ws_find_window "ChatGPT" --visible)

    # Notes: prefer non-empty title
    set -l notes (echo $windows_json | ws_find_window "Notes" --nonempty-title)

    if test -z "$notes"
        set notes (echo $windows_json | ws_find_window "Notes")
    end

    # -------------------------------------------------------------------------
    # 7. First-pass move
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $finder $preview $chatgpt $notes

    # -------------------------------------------------------------------------
    # 8. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

    set finder (echo $windows_json_final | ws_find_window "Finder" --space $target_space)

    set preview (echo $windows_json_final | ws_find_window "Preview" --space $target_space)

    set chatgpt (echo $windows_json_final | ws_find_window "ChatGPT" --space $target_space --visible)

    set notes (echo $windows_json_final | ws_find_window "Notes" --space $target_space --nonempty-title)

    if test -z "$notes"
        set notes (echo $windows_json_final | ws_find_window "Notes" --space $target_space)
    end

    # -------------------------------------------------------------------------
    # 10. Apply final layout
    #     Left 1/4 Finder, middle 3/8 Preview,
    #     right upper 3/8 ChatGPT, right lower 3/8 Notes.
    # -------------------------------------------------------------------------
    if test -n "$finder"
        ws_window $finder --grid 2:8:0:0:2:2
    end

    if test -n "$preview"
        ws_window $preview --grid 2:8:2:0:3:2
    end

    if test -n "$chatgpt"
        ws_window $chatgpt --grid 2:8:5:0:3:1
    end

    if test -n "$notes"
        ws_window $notes --grid 2:8:5:1:3:1
    end

    # -------------------------------------------------------------------------
    # 11. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    gtd_cleanup_tall_spaces
    gtd_cleanup_solo_spaces
    cleanup_unlabeled_empty_spaces $target_space
end

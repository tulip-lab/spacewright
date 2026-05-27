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
    #   Fall back to the workspace primary display if no external display is available.
    #
    # Managed apps:
    #   - Finder
    #   - Preview
    #   - ChatGPT
    #   - Notes
    #
    # Window selection rules:
    #   - Preview / Notes / ChatGPT:
    #       At least one must exist before the workspace is created. Preview is
    #       no longer required because review work often starts from Notes or
    #       ChatGPT before a PDF is open.
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
    workspace_cleanup_mode_spaces gtd tall
    workspace_cleanup_mode_spaces gtd solo
    set -l label gtd_review_wide

    # -------------------------------------------------------------------------
    # 2. Require at least one non-Finder review app before creating workspace
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows "gtd_review_wide" initial); or return 1

    set -l preview (echo $windows_json | ws_find_window "Preview")
    set -l chatgpt_initial (echo $windows_json | ws_find_window "ChatGPT")
    set -l notes_initial (echo $windows_json | ws_find_window "Notes" --nonempty-title)

    if test -z "$notes_initial"
        set notes_initial (echo $windows_json | ws_find_window "Notes")
    end

    if test -z "$preview" -a -z "$notes_initial" -a -z "$chatgpt_initial"
        destroy_empty_labeled_space $label

        return 0
    end

    # -------------------------------------------------------------------------
    # 3. Resolve target display
    #    Prefer an external display; if none exists, fall back to internal.
    # -------------------------------------------------------------------------
    set -l target_display (resolve_workspace_external_display wide)

    # -------------------------------------------------------------------------
    # 4. Find or create target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    set target_space (workspace_retarget_contaminated_space \
        gtd_review_wide \
        $label \
        $target_space \
        $target_display \
        '^(Finder|Preview|ChatGPT|Notes)$')
    or return 1

    # -------------------------------------------------------------------------
    # 5. Normalize target space state
    # -------------------------------------------------------------------------
    workspace_focus_labeled_space $label $target_space $target_display float gtd:tall gtd:solo
    or return 1

    # -------------------------------------------------------------------------
    # 6. First-pass window capture
    # -------------------------------------------------------------------------
    set -l finder (echo $windows_json | ws_find_window "Finder")

    # Notes: prefer non-empty title
    set -l notes $notes_initial

    # -------------------------------------------------------------------------
    # 7. First-pass move
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $finder $preview $notes
    set -l chatgpt (workspace_capture_app_window --app ChatGPT --caller gtd_review_wide --space $target_space)

    # -------------------------------------------------------------------------
    # 8. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows "gtd_review_wide" final); or return 1

    set finder (echo $windows_json_final | ws_find_window "Finder" --space $target_space)

    set preview (echo $windows_json_final | ws_find_window "Preview" --space $target_space)

    set chatgpt (workspace_find_app_window --app ChatGPT --caller gtd_review_wide --space $target_space --no-refresh)

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
    workspace_cleanup_mode_spaces gtd tall
    workspace_cleanup_mode_spaces gtd solo
    cleanup_unlabeled_empty_spaces $target_space
end

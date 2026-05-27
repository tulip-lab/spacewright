function coding_editor_solo --description "Collect VS Code and Codex onto the solo coding editor workspace"
    coding_cleanup_wide_spaces
    coding_cleanup_tall_spaces

    set -l label coding_editor_solo
    set -l windows_json (ws_query_windows "coding_editor_solo" initial); or return 1

    set -l code_window (echo $windows_json | ws_find_window "Code")

    if test -z "$code_window"
        destroy_empty_labeled_space $label

        return 0
    end

    set -l target_display (resolve_workspace_primary_display)
    set -l target_space (workspace_prepare_labeled_space $label $target_display float)
    or return 1

    ws_move_windows_to_space $target_space $code_window
    set -l codex_window (workspace_capture_app_window --app Codex --caller coding_editor_solo --space $target_space)

    set -l windows_json_final (ws_query_windows "coding_editor_solo" final); or return 1

    set code_window (echo $windows_json_final | ws_find_window "Code" --space $target_space)
    set codex_window (workspace_find_app_window --app Codex --caller coding_editor_solo --space $target_space --no-refresh)

    if test -n "$codex_window"
        ws_window $codex_window --grid 1:3:0:0:1:1
    end

    if test -n "$code_window"
        if test -n "$codex_window"
            ws_window $code_window --grid 1:3:1:0:2:1
        else
            ws_window $code_window --grid 1:1:0:0:1:1
        end
    end

    coding_cleanup_wide_spaces
    coding_cleanup_tall_spaces
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

function research_solo --description "Collect Zotero and ChatGPT onto the solo research workspace"
    research_cleanup_wide_spaces
    research_cleanup_tall_spaces

    set -l label research_solo
    set -l windows_json (yabai -m query --windows)

    set -l zotero_window (echo $windows_json | ws_find_window "Zotero")

    if test -z "$zotero_window"
        destroy_empty_labeled_space $label

        return 0
    end

    set -l chatgpt_window (echo $windows_json | ws_find_window "ChatGPT" --visible)

    set -l target_display (resolve_internal_display)
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    ws_focus_space $target_space
    sleep 0.15

    ws_move_app_pair_to_space \
        $target_space \
        "Zotero" $zotero_window \
        "ChatGPT" $chatgpt_window \
        --helper-visible

    set -l windows_json_final (yabai -m query --windows)

    set zotero_window (echo $windows_json_final | ws_find_window "Zotero" --space $target_space)

    set chatgpt_window (echo $windows_json_final | ws_find_window "ChatGPT" --space $target_space --visible)

    if test -n "$zotero_window"
        ws_window $zotero_window --grid 1:3:0:0:2:1
    end

    if test -n "$chatgpt_window"
        ws_window $chatgpt_window --grid 1:3:2:0:1:1
    end

    research_cleanup_wide_spaces
    research_cleanup_tall_spaces
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

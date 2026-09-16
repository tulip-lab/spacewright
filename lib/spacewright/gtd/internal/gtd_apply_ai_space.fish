function __gtd_ai_allowed_app_regex --description "Return app regex for GTD AI owned windows"
    set -l app_names

    for app_key in hermes chatgpt obsidian notes
        set -a app_names (workspace_app_names $app_key)
        or return 1
    end

    set -l escaped_names
    for app_name in $app_names
        set -a escaped_names (string escape --style=regex -- $app_name)
    end

    printf "^(%s)\$\n" (string join '|' $escaped_names)
end

function __gtd_ai_capture_app --description "Capture or open one GTD AI app window"
    argparse 'app=' 'app-key=' 'caller=' 'space=' -- $argv
    or return 1

    if not set -q _flag_app; and not set -q _flag_app_key
        echo "usage: __gtd_ai_capture_app --app <app-name>|--app-key <key> --space <space> [--caller <name>]" >&2
        return 2
    end

    if not set -q _flag_space
        echo "usage: __gtd_ai_capture_app --app <app-name>|--app-key <key> --space <space> [--caller <name>]" >&2
        return 2
    end

    set -l caller gtd_ai
    if set -q _flag_caller
        set caller $_flag_caller
    end

    set -l app_label
    set -l capture_args --caller $caller --space $_flag_space

    if set -q _flag_app_key
        set app_label (workspace_app_name $_flag_app_key)
        or return 1
        set -a capture_args --app-key $_flag_app_key
    else
        set app_label $_flag_app
        set -a capture_args --app "$_flag_app"
    end

    set -l window_id (workspace_capture_app_window $capture_args)
    set -l capture_status $status

    if test "$capture_status" -eq 1
        return 1
    end

    if test -n "$window_id"
        echo $window_id
        return 0
    end

    if test "$capture_status" -eq 2
        echo "[WARN] $caller found $app_label, but no movable layout window was available; skipping $app_label" >&2
        return 0
    end

    workspace_debug_step $caller open-$app_label
    perl -e 'alarm shift; exec @ARGV' 2 open -a "$app_label" >/dev/null 2>&1
    if test $status -ne 0
        echo "[WARN] $caller could not open $app_label; skipping $app_label" >&2
        return 0
    end

    for attempt in (seq 1 4)
        sleep 0.5

        set window_id (workspace_capture_app_window $capture_args)
        set capture_status $status

        if test "$capture_status" -eq 1
            return 1
        end

        if test -n "$window_id"
            echo $window_id
            return 0
        end

        if test "$capture_status" -eq 2
            echo "[WARN] $caller opened $app_label, but no movable layout window was available; skipping $app_label" >&2
            return 0
        end
    end

    echo "[WARN] $caller opened $app_label, but no window appeared; skipping $app_label" >&2
    return 0
end

function gtd_ai_detect_display_mode --description "Detect the current GTD AI display mode"
    workspace_detect_display_mode
end

function gtd_ai_expand_hermes_when_alone --description "Expand Hermes when it is the only effective GTD AI window"
    set -l spaces_json (ws_query_spaces gtd_ai_expand_hermes_when_alone spaces)
    or return 1
    set -l windows_json (ws_query_windows gtd_ai_expand_hermes_when_alone windows)
    or return 1

    set -l ai_spaces (echo $spaces_json | ws_jq -r '.[] | select(.label == "gtd_ai") | .index')
    or return 1
    if test (count $ai_spaces) -eq 0
        return 0
    end
    if test (count $ai_spaces) -ne 1
        echo "[WARN] gtd_ai has duplicate labeled Spaces; cannot safely reflow Hermes" >&2
        return 1
    end

    set -l occupant_windows (echo $windows_json | workspace_space_occupant_windows_json)
    or return 1
    set -l hermes_apps_json (workspace_app_names_json hermes)
    or return 1
    set -l hermes_id (echo $occupant_windows | ws_jq -r \
        --argjson space $ai_spaces[1] \
        --argjson apps "$hermes_apps_json" '
            [.[] | select(.space == $space)] as $ai_windows
            | if ($ai_windows | length) == 1
                and ($ai_windows[0].app as $app | $apps | index($app)) != null
                and $ai_windows[0]["can-move"] == true
            then $ai_windows[0].id
            else empty
            end
        ')
    or return 1

    if test -n "$hermes_id"
        ws_window $hermes_id --grid 1:1:0:0:1:1
    end
end

function gtd_apply_ai_space --description "Apply a GTD AI workspace for Hermes, ChatGPT, Obsidian and Notes"
    argparse \
        'label=' \
        'display=' \
        'hermes-grid=' \
        'chatgpt-grid=' \
        'obsidian-grid=' \
        'notes-grid=' \
        dry-run \
        -- $argv
    or return 1

    if not set -q _flag_label; or not set -q _flag_display
        echo "usage: gtd_apply_ai_space --label <label> --display <primary|wide|tall> [grid options] [cleanup-spec ...]" >&2
        return 2
    end

    set -l cleanup_specs $argv

    if set -q _flag_dry_run
        printf "dry_run=gtd_apply_ai_space\n"
        printf "label=%s\n" "$_flag_label"
        printf "display=%s\n" "$_flag_display"
        printf "apps=%s,%s,%s,%s\n" (workspace_app_name hermes) (workspace_app_name chatgpt) (workspace_app_name obsidian) (workspace_app_name notes)
        printf "hermes_grid=%s\n" "$_flag_hermes_grid"
        printf "chatgpt_grid=%s\n" "$_flag_chatgpt_grid"
        printf "obsidian_grid=%s\n" "$_flag_obsidian_grid"
        printf "notes_grid=%s\n" "$_flag_notes_grid"
        printf "cleanup=%s\n" "$cleanup_specs"
        return 0
    end

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    set -l target_display (workspace_resolve_display_role $_flag_display)
    or return $status

    set -l allowed_app_regex (__gtd_ai_allowed_app_regex)
    or return 1

    set -l target_space (find_or_create_labeled_space $_flag_label $target_display)
    if test -z "$target_space"
        return 1
    end

    set target_space (workspace_retarget_contaminated_space \
        $_flag_label \
        $_flag_label \
        $target_space \
        $target_display \
        "$allowed_app_regex")
    or return 1

    workspace_focus_labeled_space $_flag_label $target_space $target_display float
    or return 1

    set -l hermes (__gtd_ai_capture_app --app-key hermes --caller $_flag_label --space $target_space)
    or return 1

    set -l chatgpt (__gtd_ai_capture_app --app-key chatgpt --caller $_flag_label --space $target_space)
    or return 1

    set -l obsidian (__gtd_ai_capture_app --app-key obsidian --caller $_flag_label --space $target_space)
    or return 1

    set -l notes (__gtd_ai_capture_app --app-key notes --caller $_flag_label --space $target_space)
    or return 1

    if test -z "$hermes" -a -z "$chatgpt" -a -z "$obsidian" -a -z "$notes"
        destroy_empty_labeled_space $_flag_label
        return 0
    end

    if test -n "$hermes" -a -n "$_flag_hermes_grid"
        ws_window $hermes --grid $_flag_hermes_grid
    end

    if test -n "$chatgpt" -a -n "$_flag_chatgpt_grid"
        ws_window $chatgpt --grid $_flag_chatgpt_grid
    end

    if test -n "$obsidian" -a -n "$_flag_obsidian_grid"
        ws_window $obsidian --grid $_flag_obsidian_grid
    end

    if test -n "$notes" -a -n "$_flag_notes_grid"
        ws_window $notes --grid $_flag_notes_grid
    end

    ws_focus_space $target_space

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    cleanup_unlabeled_empty_spaces $target_space
end

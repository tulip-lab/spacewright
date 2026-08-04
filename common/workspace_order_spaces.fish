function __workspace_order_labels_on_display --description "Order existing labeled Spaces on one display"
    argparse 'display=' preserve-leading-unlabeled -- $argv
    or return 1

    if not set -q _flag_display
        echo "usage: __workspace_order_labels_on_display --display <index> [--preserve-leading-unlabeled] <label>..." >&2
        return 2
    end

    set -l labels $argv
    set -l initial_spaces (ws_query_spaces workspace_order_spaces initial)
    or return 1

    set -l target_index (echo $initial_spaces | ws_jq -r --argjson display "$_flag_display" '
        [.[] | select(.display == $display) | .index] | min // empty
    ')
    if test -z "$target_index"
        return 0
    end

    if set -q _flag_preserve_leading_unlabeled
        set -l first_label (echo $initial_spaces | ws_jq -r --argjson display "$_flag_display" '
            ([.[] | select(.display == $display)] | sort_by(.index) | first | .label) // empty
        ')
        if test -z "$first_label"
            set target_index (math $target_index + 1)
        end
    end

    for label in $labels
        set -l live_spaces (ws_query_spaces workspace_order_spaces "before-$label")
        or return 1

        set -l source_index (echo $live_spaces | ws_jq -r \
            --argjson display "$_flag_display" \
            --arg label "$label" '
                first(.[] | select(.display == $display and .label == $label) | .index) // empty
            ')
        if test -z "$source_index"
            continue
        end

        if test "$source_index" -ne "$target_index"
            ws_yabai -m space "$label" --move "$target_index"
            or return 1
        end

        set target_index (math $target_index + 1)
    end
end

function workspace_order_mode_spaces --description "Order existing primary and external workspace Spaces"
    argparse dry-run -- $argv
    or return 1

    set -l mode $argv[1]
    if not contains -- "$mode" wide tall
        echo "usage: workspace_order_mode_spaces [--dry-run] <wide|tall>" >&2
        return 2
    end

    set -l primary_labels coding_control gtd_chat gtd_calendar
    set -l external_labels \
        gtd_ai \
        coding_editor_$mode \
        research_$mode \
        office_writing_$mode \
        office_slides_$mode \
        gtd_support_$mode \
        gtd_review_$mode \
        gtd_mail_$mode \
        gtd_meeting_$mode

    if set -q _flag_dry_run
        printf "dry_run=workspace_order_mode_spaces\n"
        printf "mode=%s\n" "$mode"
        printf "primary=%s\n" (string join , $primary_labels)
        printf "external=%s\n" (string join , $external_labels)
        return 0
    end

    set -l primary_display (resolve_workspace_primary_display)
    or return 1
    set -l external_display (workspace_resolve_display_role $mode)
    or return 1

    __workspace_order_labels_on_display \
        --display $primary_display \
        --preserve-leading-unlabeled \
        $primary_labels
    or return 1

    __workspace_order_labels_on_display \
        --display $external_display \
        $external_labels
end

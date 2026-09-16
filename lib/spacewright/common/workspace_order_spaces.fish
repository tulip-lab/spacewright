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
        set -l home_info (echo $initial_spaces | ws_jq -r --argjson display "$_flag_display" '
            [.[] | select(.display == $display and .label == "")]
            | sort_by(.index)
            | first
            | if . == null then empty else [.uuid, .index] | @tsv end
        ')

        if test -n "$home_info"
            set -l home_parts (string split \t -- "$home_info")
            set -l home_uuid $home_parts[1]
            set -l home_index $home_parts[2]

            if test -z "$home_uuid" -o -z "$home_index"
                return 1
            end

            if test "$home_index" -ne "$target_index"
                ws_yabai -m space "$home_index" --move "$target_index"
                or return 1
            end

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

function workspace_primary_order_labels --description "Print primary-display workspace labels in order"
    printf "%s\n" coding_control gtd_chat gtd_calendar
end

function workspace_solo_order_labels --description "Print solo primary-display workspace labels in order"
    printf "%s\n" \
        (workspace_primary_order_labels) \
        gtd_ai \
        coding_editor_solo \
        research_solo \
        gtd_support_solo \
        gtd_review_solo \
        gtd_mail_solo \
        gtd_meeting_solo \
        sandbox_solo
end

function workspace_external_order_labels --description "Print external workspace labels in mode order"
    set -l mode $argv[1]
    if not contains -- $mode wide tall
        echo "usage: workspace_external_order_labels <wide|tall>" >&2
        return 2
    end

    printf "%s\n" \
        gtd_ai \
        coding_editor_$mode \
        research_$mode \
        office_writing_$mode \
        office_slides_$mode \
        gtd_support_$mode \
        gtd_review_$mode \
        gtd_mail_$mode \
        gtd_meeting_$mode \
        sandbox_$mode
end

function workspace_order_mode_spaces --description "Order existing primary and external workspace Spaces"
    argparse dry-run -- $argv
    or return 1

    set -l mode $argv[1]
    if not contains -- "$mode" solo wide tall
        echo "usage: workspace_order_mode_spaces [--dry-run] <solo|wide|tall>" >&2
        return 2
    end

    set -l primary_labels
    set -l external_labels
    if test "$mode" = solo
        set primary_labels (workspace_solo_order_labels)
    else
        set primary_labels (workspace_primary_order_labels)
        set external_labels (workspace_external_order_labels $mode)
    end

    if set -q _flag_dry_run
        printf "dry_run=workspace_order_mode_spaces\n"
        printf "mode=%s\n" "$mode"
        printf "primary=%s\n" (string join , $primary_labels)
        if test "$mode" != solo
            printf "external=%s\n" (string join , $external_labels)
        end
        return 0
    end

    set -l primary_display (resolve_workspace_primary_display)
    or return 1

    __workspace_order_labels_on_display \
        --display $primary_display \
        --preserve-leading-unlabeled \
        $primary_labels
    or return 1

    if test "$mode" = solo
        return 0
    end

    set -l external_display (workspace_resolve_display_role $mode)
    or return 1

    __workspace_order_labels_on_display \
        --display $external_display \
        $external_labels
end

function __workspace_verify_order_prefix --description "Verify managed labels form a display prefix"
    argparse 'display=' 'spaces-json=' preserve-leading-home -- $argv
    or return 1

    if not set -q _flag_display; or not set -q _flag_spaces_json
        return 2
    end

    set -l labels $argv
    set -l actual (echo $_flag_spaces_json | ws_jq -r --argjson display $_flag_display '
        [.[] | select(.display==$display)] | sort_by(.index) | .[]
        | if .label=="" then "__UNMANAGED__" else .label end
    ')
    or return 1

    if set -q _flag_preserve_leading_home
        set -l home_index (echo $_flag_spaces_json | ws_jq -r --argjson display $_flag_display '
            [.[] | select(.display==$display and .label=="") | .index] | min // empty
        ')
        if test -n "$home_index"
            set -l first_index (echo $_flag_spaces_json | ws_jq -r --argjson display $_flag_display '
                [.[] | select(.display==$display) | .index] | min // empty
            ')
            test "$home_index" = "$first_index"; or return 1
            set actual $actual[2..-1]
        end
    end

    set -l expected
    for label in $labels
        echo $_flag_spaces_json | ws_jq -e --argjson display $_flag_display --arg label "$label" \
            'any(.[]; .display==$display and .label==$label)' >/dev/null
        and set -a expected $label
    end

    if test (count $expected) -gt 0
        for index in (seq (count $expected))
            test "$actual[$index]" = "$expected[$index]"
            or return 1
        end
    end
end

function workspace_verify_mode_space_order --description "Verify Home and managed label prefixes for a mode"
    set -l mode $argv[1]
    if not contains -- $mode solo wide tall
        echo "usage: workspace_verify_mode_space_order <solo|wide|tall>" >&2
        return 2
    end

    set -l primary_display (resolve_workspace_primary_display)
    or return 1
    set -l spaces_json (ws_query_spaces workspace_verify_mode_space_order verify)
    or return 1

    set -l primary_labels (workspace_primary_order_labels)
    if test "$mode" = solo
        set primary_labels (workspace_solo_order_labels)
    end

    __workspace_verify_order_prefix \
        --display $primary_display \
        --spaces-json "$spaces_json" \
        --preserve-leading-home \
        $primary_labels
    or return 1

    if test "$mode" = solo
        return 0
    end

    set -l external_display (workspace_resolve_display_role $mode)
    or return 1

    __workspace_verify_order_prefix \
        --display $external_display \
        --spaces-json "$spaces_json" \
        (workspace_external_order_labels $mode)
end

function workspace_order_and_verify_mode_spaces --description "Order and verify mode Spaces with one retry"
    set -l mode $argv[1]
    if not contains -- $mode solo wide tall
        echo "usage: workspace_order_and_verify_mode_spaces <solo|wide|tall>" >&2
        return 2
    end

    for attempt in 1 2
        workspace_order_mode_spaces $mode
        or return 1
        workspace_verify_mode_space_order $mode
        and return 0
        echo "[WARN] Space order verification drift for $mode attempt=$attempt" >&2
    end

    return 1
end

function cleanup_labeled_empty_spaces --description "Destroy empty spaces whose labels match a regex"
    if test "$WORKSPACE_SKIP_LABELED_CLEANUP" = "1"
        return 0
    end

    set -l label_pattern $argv[1]
    set -l display_name $argv[2]

    if test -z "$label_pattern"
        return 1
    end

    if test -z "$display_name"
        set display_name "labeled"
    end

    set -l spaces_json (ws_query_spaces cleanup_labeled_empty_spaces cleanup)
    if test $status -ne 0 -o -z "$spaces_json"
        return 0
    end

    set -l candidates (echo $spaces_json | ws_jq -r --arg pattern "$label_pattern" '
        [.[]
        | select(.label | test($pattern))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty $display_name space: $s"
        ws_yabai -m space $s --destroy >/dev/null 2>&1
    end
end

function cleanup_unlabeled_empty_spaces --description "Remove unlabeled empty spaces on all displays except a protected space"
    set -l protected_space $argv[1]

    if test -z "$protected_space"
        set -l current_space_json (ws_query_current_space cleanup_unlabeled_empty_spaces protected-space)
        if test $status -ne 0 -o -z "$current_space_json"
            return 0
        end

        set protected_space (echo $current_space_json | ws_jq -r '.index')
    end

    if test -z "$protected_space"
        return 0
    end

    set -l spaces_json (ws_query_spaces cleanup_unlabeled_empty_spaces cleanup)
    if test $status -ne 0 -o -z "$spaces_json"
        return 0
    end

    set -l cleanup_spaces (
        echo $spaces_json | ws_jq -r \
            --argjson protected "$protected_space" \
            '.[]
             | select(.label=="")
             | select((.windows | length)==0)
             | select(.index!=$protected)
             | .index' \
        | sort -nr
    )

    for s in $cleanup_spaces
        if test -n "$s"
            ws_yabai -m space $s --destroy >/dev/null 2>&1
            sleep 0.05
        end
    end
end

function workspace_cleanup_mode_spaces --description "Destroy empty labeled spaces for a workspace family and mode"
    set -l family $argv[1]
    set -l mode $argv[2]

    if test -z "$family" -o -z "$mode"
        echo "usage: workspace_cleanup_mode_spaces <coding|gtd|office|research> <solo|wide|tall>" >&2
        return 2
    end

    switch "$mode"
        case solo wide tall
        case "*"
            echo "[WARN] workspace_cleanup_mode_spaces: invalid mode: $mode" >&2
            return 2
    end

    switch "$family"
        case coding
            cleanup_labeled_empty_spaces "^coding_.*_$mode\$" "Coding $mode"
        case gtd
            cleanup_labeled_empty_spaces "^gtd_.*_$mode\$" "GTD $mode"
        case office
            cleanup_labeled_empty_spaces "^office_.*_$mode\$" "Office $mode"
        case research
            cleanup_labeled_empty_spaces "^research(_.*)?_$mode\$" "Research $mode"
        case "*"
            echo "[WARN] workspace_cleanup_mode_spaces: invalid family: $family" >&2
            return 2
    end
end

function workspace_cleanup_known_labeled_spaces --description "Destroy empty spaces with known workspace labels"
    set -l workspace_label_pattern '^(coding_.*_(solo|wide|tall)|coding_control|gtd_.*_(solo|wide|tall)|gtd_chat|gtd_calendar|office_.*_(solo|wide|tall)|research(_.*)?_(solo|wide|tall))$'

    cleanup_labeled_empty_spaces "$workspace_label_pattern" "workspace labeled"
end

function work_recover_light --description "Run conservative workspace recovery without moving or laying out windows"
    echo "===== BEFORE RECOVERY ====="
    work_diagnostics

    echo
    echo "===== CLEAN EMPTY LABELED SPACES ====="
    workspace_cleanup_known_labeled_spaces

    echo
    echo "===== CLEAN EMPTY UNLABELED SPACES ====="
    cleanup_unlabeled_empty_spaces

    echo
    echo "===== AFTER RECOVERY ====="
    work_diagnostics
end

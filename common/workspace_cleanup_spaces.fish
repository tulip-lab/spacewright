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

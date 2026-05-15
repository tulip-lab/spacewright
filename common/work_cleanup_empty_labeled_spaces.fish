function work_cleanup_empty_labeled_spaces --description "Destroy empty spaces with known workspace labels"
    set -l workspace_label_pattern '^(coding_.*_(solo|wide|tall)|coding_control|gtd_.*_(solo|wide|tall)|gtd_chat|gtd_calendar|office_.*_(solo|wide|tall)|research(_.*)?_(solo|wide|tall))$'

    cleanup_labeled_empty_spaces "$workspace_label_pattern" "workspace labeled"
end

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

function work_recover_light --description "Run conservative workspace recovery without moving or laying out windows"
    echo "===== BEFORE RECOVERY ====="
    work_diagnostics

    echo
    echo "===== CLEAN EMPTY LABELED SPACES ====="
    work_cleanup_empty_labeled_spaces

    echo
    echo "===== CLEAN EMPTY UNLABELED SPACES ====="
    work_cleanup_empty_unlabeled_spaces

    echo
    echo "===== AFTER RECOVERY ====="
    work_diagnostics
end

function office_cleanup_tall_spaces --description "Destroy empty labeled office tall spaces"
    cleanup_labeled_empty_spaces '^office_.*_tall$' 'Office tall'
end

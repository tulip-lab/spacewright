function office_cleanup_wide_spaces --description "Destroy empty labeled office wide spaces"
    cleanup_labeled_empty_spaces '^office_.*_wide$' 'Office wide'
end

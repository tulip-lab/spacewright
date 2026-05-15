function coding_cleanup_wide_spaces --description "Destroy empty labeled coding wide spaces"
    cleanup_labeled_empty_spaces '^coding_.*_wide$' 'Coding wide'
end

function coding_cleanup_tall_spaces --description "Destroy empty labeled coding tall spaces"
    cleanup_labeled_empty_spaces '^coding_.*_tall$' 'Coding tall'
end

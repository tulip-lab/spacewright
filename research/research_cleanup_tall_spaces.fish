function research_cleanup_tall_spaces --description "Destroy empty labeled research tall spaces"
    cleanup_labeled_empty_spaces '^research(_.*)?_tall$' 'Research tall'
end

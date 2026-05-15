function gtd_cleanup_tall_spaces --description "Destroy empty labeled GTD tall spaces"
    cleanup_labeled_empty_spaces '^gtd_.*_tall$' 'GTD tall'
end

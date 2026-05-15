function gtd_cleanup_wide_spaces --description "Destroy empty labeled GTD wide spaces"
    cleanup_labeled_empty_spaces '^gtd_.*_wide$' 'GTD wide'
end

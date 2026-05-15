function research_cleanup_wide_spaces --description "Destroy empty labeled research wide spaces"
    cleanup_labeled_empty_spaces '^research(_.*)?_wide$' 'Research wide'
end

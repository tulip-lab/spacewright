function research_cleanup_solo_spaces --description "Destroy empty labeled research solo spaces"
    cleanup_labeled_empty_spaces '^research(_.*)?_solo$' 'Research solo'
end

function gtd_cleanup_solo_spaces --description "Destroy empty labeled GTD solo spaces"
    cleanup_labeled_empty_spaces '^gtd_.*_solo$' 'GTD solo'
end

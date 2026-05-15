function coding_cleanup_solo_spaces --description "Destroy empty labeled coding solo spaces"
    cleanup_labeled_empty_spaces '^coding_.*_solo$' 'Coding solo'
end

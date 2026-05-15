function office_cleanup_solo_spaces --description "Destroy empty labeled office solo spaces"
    cleanup_labeled_empty_spaces '^office_.*_solo$' 'Office solo'
end

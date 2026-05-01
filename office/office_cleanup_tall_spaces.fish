function office_cleanup_tall_spaces
    set candidates (yabai -m query --spaces | jq -r '
        [.[]
        | select(.label | test("^office_.*_tall$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Office tall space: $s"
        yabai -m space $s --destroy
    end
end
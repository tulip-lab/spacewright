function research_cleanup_tall_spaces
    set candidates (yabai -m query --spaces | jq -r '
        [.[]
        | select(.label | test("^research.*_tall$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Research tall space: $s"
        yabai -m space $s --destroy
    end
end
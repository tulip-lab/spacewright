function coding_cleanup_tall_spaces
    set candidates (yabai -m query --spaces | jq -r '
        [.[]
        | select(.label | test("^coding_.*_tall$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Coding tall space: $s"
        yabai -m space $s --destroy
    end
end
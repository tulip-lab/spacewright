function gtd_cleanup_tall_spaces
    set candidates (yabai -m query --spaces | jq -r '
        [.[]
        | select(.label | test("^gtd_.*_tall$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty GTD tall space: $s"
        yabai -m space $s --destroy
    end
end
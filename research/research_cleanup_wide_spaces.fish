function research_cleanup_wide_spaces
    set candidates (yabai -m query --spaces | jq -r '
        [.[]
        | select((.label | test("^research.*_wide$")) or (.label == "research_wide"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Research wide space: $s"
        yabai -m space $s --destroy
    end
end
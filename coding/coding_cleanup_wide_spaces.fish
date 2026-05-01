function coding_cleanup_wide_spaces
    set candidates (yabai -m query --spaces | jq -r '
        [.[]
        | select(.label | test("^coding_.*_wide$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Coding wide space: $s"
        yabai -m space $s --destroy
    end
end
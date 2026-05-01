function office_cleanup_wide_spaces
    set candidates (yabai -m query --spaces | jq -r '
        [.[]
        | select(.label | test("^office_.*_wide$"))
        | select((.windows | length) == 0)
        | .index]
        | sort
        | reverse
        | .[]
    ')

    for s in $candidates
        echo "Destroying empty Office wide space: $s"
        yabai -m space $s --destroy
    end
end
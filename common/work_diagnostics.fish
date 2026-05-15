function work_diagnostics --description "Show workspace diagnostics without changing spaces or windows"
    set -l displays_json (yabai -m query --displays 2>/dev/null)
    set -l spaces_json (yabai -m query --spaces 2>/dev/null)
    set -l windows_json (yabai -m query --windows 2>/dev/null)

    echo "===== DISPLAY SUMMARY ====="
    echo $displays_json | jq '.[] | {
        index,
        uuid,
        frame,
        has_focus: .["has-focus"],
        space_count: (.spaces | length),
        spaces
    }'

    echo
    echo "===== CURRENT FOCUS ====="
    set -l current_display (yabai -m query --displays --display 2>/dev/null | jq -r '.index // empty')
    set -l current_space (yabai -m query --spaces --space 2>/dev/null | jq -r '.index // empty')
    jq -n \
        --arg display "$current_display" \
        --arg space "$current_space" \
        '{display: ($display | tonumber?), space: ($space | tonumber?)}'

    echo
    echo "===== LABELED SPACE SUMMARY ====="
    echo $spaces_json | jq '
        map(select(.label != ""))
        | group_by(.label)
        | .[]
        | {
            label: .[0].label,
            count: length,
            displays: (map(.display) | unique),
            spaces: map({
                index,
                display,
                window_count: (.windows | length),
                windows
            })
        }'

    echo
    echo "===== EMPTY LABELED SPACES ====="
    if echo $spaces_json | jq -e 'any(.[]; .label != "" and (.windows | length) == 0)' >/dev/null
        echo $spaces_json | jq '.[] | select(.label != "" and (.windows | length) == 0) | {index, label, display}'
    else
        echo "none"
    end

    echo
    echo "===== DUPLICATE LABELS ====="
    if echo $spaces_json | jq -e '
        map(select(.label != ""))
        | group_by(.label)
        | .[]
        | select(length > 1)' >/dev/null
        echo $spaces_json | jq '
            map(select(.label != ""))
            | group_by(.label)
            | .[]
            | select(length > 1)
            | {
            label: .[0].label,
            spaces: map({
                index,
                display,
                window_count: (.windows | length),
                windows
            })
        }'
    else
        echo "none"
    end

    echo
    echo "===== EMPTY UNLABELED SPACES ====="
    if echo $spaces_json | jq -e 'any(.[]; .label == "" and (.windows | length) == 0)' >/dev/null
        echo $spaces_json | jq '.[] | select(.label == "" and (.windows | length) == 0) | {index, display}'
    else
        echo "none"
    end

    echo
    work_bad_windows
end

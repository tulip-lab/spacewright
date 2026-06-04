function work_diagnostics --description "Show workspace diagnostics without changing spaces or windows"
    set -l displays_json (ws_query_displays work_diagnostics summary)
    if test $status -ne 0 -o -z "$displays_json"
        set displays_json "[]"
    end

    set -l spaces_json (ws_query_spaces work_diagnostics summary)
    if test $status -ne 0 -o -z "$spaces_json"
        set spaces_json "[]"
    end

    set -l windows_json (ws_query_windows work_diagnostics summary)
    if test $status -ne 0 -o -z "$windows_json"
        set windows_json "[]"
    end

    echo "===== DISPLAY SUMMARY ====="
    echo $displays_json | ws_jq '.[] | {
        index,
        uuid,
        frame,
        has_focus: .["has-focus"],
        space_count: (.spaces | length),
        spaces
    }'

    echo
    echo "===== DISPLAY ROLE HEALTH ====="
    work_display_health

    echo
    echo "===== CURRENT FOCUS ====="
    set -l current_display_json (ws_query_current_display work_diagnostics current-focus)
    set -l current_space_json (ws_query_current_space work_diagnostics current-focus)
    set -l current_display
    set -l current_space

    if test -n "$current_display_json"
        set current_display (echo $current_display_json | ws_jq -r '.index // empty')
    end

    if test -n "$current_space_json"
        set current_space (echo $current_space_json | ws_jq -r '.index // empty')
    end
    ws_jq -n \
        --arg display "$current_display" \
        --arg space "$current_space" \
        '{display: ($display | tonumber?), space: ($space | tonumber?)}'

    echo
    echo "===== LABELED SPACE SUMMARY ====="
    echo $spaces_json | ws_jq '
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
    if echo $spaces_json | ws_jq -e 'any(.[]; .label != "" and (.windows | length) == 0)' >/dev/null
        echo $spaces_json | ws_jq '.[] | select(.label != "" and (.windows | length) == 0) | {index, label, display}'
    else
        echo "none"
    end

    echo
    echo "===== DUPLICATE LABELS ====="
    if echo $spaces_json | ws_jq -e '
        map(select(.label != ""))
        | group_by(.label)
        | .[]
        | select(length > 1)' >/dev/null
        echo $spaces_json | ws_jq '
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
    if echo $spaces_json | ws_jq -e 'any(.[]; .label == "" and (.windows | length) == 0)' >/dev/null
        echo $spaces_json | ws_jq '.[] | select(.label == "" and (.windows | length) == 0) | {index, display}'
    else
        echo "none"
    end

    echo
    work_bad_windows --summary
end

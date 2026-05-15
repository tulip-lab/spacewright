function workspace_status_snapshot --description "Print common display and space status sections"
    set -l displays_json (ws_yabai -m query --displays 2>/dev/null)
    if test $status -ne 0 -o -z "$displays_json"
        echo "[WARN] workspace_status_snapshot could not query displays from yabai" >&2
        set displays_json "[]"
    end

    set -l spaces_json (ws_yabai -m query --spaces 2>/dev/null)
    if test $status -ne 0 -o -z "$spaces_json"
        echo "[WARN] workspace_status_snapshot could not query spaces from yabai" >&2
        set spaces_json "[]"
    end

    echo "===== DISPLAYS ====="
    echo $displays_json | jq '.[] | {
        index,
        uuid,
        frame,
        has_focus: .["has-focus"],
        space_count: (.spaces | length),
        spaces
    }'

    echo
    echo "===== SPACES ====="
    echo $spaces_json | jq '.[] | {
        index,
        label,
        display,
        window_count: (.windows | length),
        windows
    }'
end

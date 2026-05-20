function ws_query_windows --description "Query yabai windows with timeout and fail-closed warning"
    set -l caller $argv[1]
    set -l phase $argv[2]

    if test -z "$caller"
        set caller workspace
    end

    if test -z "$phase"
        set phase windows
    end

    set -l windows_json (ws_yabai -m query --windows 2>/dev/null)
    if test $status -ne 0 -o -z "$windows_json"
        echo "[WARN] $caller could not query $phase windows from yabai" >&2
        return 1
    end

    echo $windows_json | ws_jq -e 'type == "array"' >/dev/null 2>&1
    if test $status -ne 0
        echo "[WARN] $caller received invalid $phase windows JSON from yabai" >&2
        return 1
    end

    echo $windows_json
end

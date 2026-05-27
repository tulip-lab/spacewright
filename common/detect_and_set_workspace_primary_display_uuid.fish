function detect_and_set_workspace_primary_display_uuid --description "Detect and set the workspace primary display UUID"
    if not command -q yabai
        echo "[WARN] yabai is not available; cannot detect workspace primary display UUID" >&2
        return 1
    end

    if not command -q jq
        echo "[WARN] jq is not available; cannot detect workspace primary display UUID" >&2
        return 1
    end

    set -l displays_json (ws_yabai -m query --displays 2>/dev/null)
    if test $status -ne 0 -o -z "$displays_json"
        echo "[WARN] Could not query displays from yabai" >&2
        return 1
    end

    set -l display_count (echo $displays_json | ws_jq -r 'length')
    if test -z "$display_count" -o "$display_count" -eq 0
        echo "[WARN] No displays returned by yabai" >&2
        return 1
    end

    set -l configured_uuid (get_workspace_primary_display_uuid 2>/dev/null)
    if test -n "$configured_uuid"
        set -l configured_match (echo $displays_json | ws_jq -r --arg uuid "$configured_uuid" '
            first(.[] | select(.uuid==$uuid) | .uuid) // empty
        ')

        if test -n "$configured_match"
            set_workspace_primary_display_uuid $configured_match >/dev/null
            echo "[OK] Existing workspace primary display UUID is connected: $configured_match"
            return 0
        end

        echo "[WARN] Configured workspace primary display UUID is not currently connected: $configured_uuid" >&2
    end

    if test "$display_count" -eq 1
        set -l only_uuid (echo $displays_json | ws_jq -r '.[0].uuid')
        if test -n "$only_uuid" -a "$only_uuid" != "null"
            set_workspace_primary_display_uuid $only_uuid
            echo "[OK] Workspace primary display UUID detected from single display: $only_uuid"
            return 0
        end

        echo "[WARN] Single display found, but UUID is missing" >&2
        return 1
    end

    if command -q displayplacer
        set -l built_in_uuid (displayplacer list 2>/dev/null | awk '
            /^Persistent screen id:/ { id=$4 }
            /^Type: MacBook built in screen/ { print id; exit }
        ')

        if test -n "$built_in_uuid"
            set -l built_in_match (echo $displays_json | ws_jq -r --arg uuid "$built_in_uuid" '
                first(.[] | select(.uuid==$uuid) | .uuid) // empty
            ')

            if test -n "$built_in_match"
                set_workspace_primary_display_uuid $built_in_match
                echo "[OK] Workspace primary display UUID detected from MacBook built-in display: $built_in_match"
                return 0
            end
        end
    end

    echo "[WARN] Could not confidently determine the workspace primary display UUID" >&2
    echo "[INFO] Candidate displays from yabai:" >&2
    echo $displays_json | ws_jq -r '
        .[]
        | [
            "index=\(.index)",
            "uuid=\(.uuid)",
            "focus=\(.[\"has-focus\"])",
            "frame=(\(.frame.x),\(.frame.y),\(.frame.w),\(.frame.h))"
        ]
        | join("  ")
    ' >&2

    echo "[INFO] Please set it manually with:" >&2
    echo "       set_workspace_primary_display_uuid <DISPLAY-UUID>" >&2

    return 1
end

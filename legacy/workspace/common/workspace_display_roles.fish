function set_workspace_primary_display_uuid --description "Persist the workspace primary display UUID"
    if test (count $argv) -lt 1
        echo "usage: set_workspace_primary_display_uuid <display_uuid>"
        return 1
    end

    set -U WORKSPACE_PRIMARY_DISPLAY_UUID $argv[1]
    echo "WORKSPACE_PRIMARY_DISPLAY_UUID set to: $WORKSPACE_PRIMARY_DISPLAY_UUID"
end

function get_workspace_primary_display_uuid --description "Return the configured workspace primary display UUID"
    if test -n "$WORKSPACE_PRIMARY_DISPLAY_UUID"
        echo $WORKSPACE_PRIMARY_DISPLAY_UUID
        return 0
    end

    return 1
end

function detect_and_set_workspace_primary_display_uuid --description "Detect and set the workspace primary display UUID"
    if not command -q yabai
        echo "[WARN] yabai is not available; cannot detect workspace primary display UUID" >&2
        return 1
    end

    if not command -q jq
        echo "[WARN] jq is not available; cannot detect workspace primary display UUID" >&2
        return 1
    end

    set -l displays_json (ws_query_displays detect_and_set_workspace_primary_display_uuid detect)
    or return 1

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

function resolve_workspace_primary_display --description "Resolve the workspace primary display index"
    set -l displays_json (ws_query_displays resolve_workspace_primary_display primary)
    or return 1

    set -l display_count (echo $displays_json | ws_jq -r 'length')
    if test -z "$display_count" -o "$display_count" -eq 0
        echo "[WARN] resolve_workspace_primary_display: no displays available" >&2
        return 1
    end

    if test "$display_count" -eq 1
        echo $displays_json | ws_jq -r '.[0].index'
        return 0
    end

    set -l primary_uuid (get_workspace_primary_display_uuid 2>/dev/null)
    if test -z "$primary_uuid"
        echo "[WARN] resolve_workspace_primary_display: workspace primary display UUID is not configured" >&2
        return 1
    end

    set -l primary_display (echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" '
        first(.[] | select(.uuid==$uuid) | .index) // empty
    ')

    if test -z "$primary_display"
        echo "[WARN] resolve_workspace_primary_display: configured primary display UUID is not present: $primary_uuid" >&2
        return 1
    end

    echo $primary_display
end

function resolve_workspace_external_display --description "Resolve the preferred non-primary workspace display index"
    set -l expected_mode $argv[1]

    switch "$expected_mode"
        case "" wide tall
        case "*"
            echo "[WARN] resolve_workspace_external_display expected mode must be one of: wide, tall" >&2
            return 2
    end

    set -l displays_json (ws_query_displays resolve_workspace_external_display external)
    or return 1

    set -l display_count (echo $displays_json | ws_jq -r 'length')
    if test -z "$display_count" -o "$display_count" -eq 0
        echo "[WARN] resolve_workspace_external_display: no displays available" >&2
        return 1
    end

    if test "$display_count" -eq 1
        echo $displays_json | ws_jq -r '.[0].index'
        return 0
    end

    set -l primary_uuid (get_workspace_primary_display_uuid 2>/dev/null)
    if test -z "$primary_uuid"
        echo "[WARN] resolve_workspace_external_display: workspace primary display UUID is not configured" >&2
        return 1
    end

    set -l external_display (echo $displays_json | ws_jq -r \
        --arg uuid "$primary_uuid" \
        --arg expected_mode "$expected_mode" '
        def matches_expected_mode:
            if $expected_mode == "wide" then .frame.w > .frame.h
            elif $expected_mode == "tall" then .frame.h > .frame.w
            else true end;

        first(
            .[]
            | select(.uuid != $uuid)
            | select(matches_expected_mode)
            | .index
        )
        // first(.[] | select(.uuid != $uuid) | .index)
        // empty
    ')

    if test -n "$external_display"
        echo $external_display
        return 0
    end

    resolve_workspace_primary_display
end

function workspace_resolve_display_role --description "Resolve a workspace display role to a yabai display index"
    set -l role $argv[1]

    switch "$role"
        case primary solo
            resolve_workspace_primary_display
        case wide tall
            resolve_workspace_external_display $role
        case '*'
            echo "[WARN] workspace_resolve_display_role: invalid display role: $role" >&2
            return 2
    end
end

function workspace_detect_display_mode --description "Detect solo, wide, or tall from connected displays"
    set -l displays_json (ws_query_displays workspace_detect_display_mode display_mode)
    or return 1

    set -l display_count (echo $displays_json | ws_jq -r 'length')
    if test -z "$display_count" -o "$display_count" -le 1
        echo solo
        return 0
    end

    set -l primary_uuid (get_workspace_primary_display_uuid 2>/dev/null)
    if test -z "$primary_uuid"
        echo "[WARN] workspace_detect_display_mode: primary display UUID is not configured" >&2
        return 1
    end

    set -l primary_present (echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" '
        first(.[] | select(.uuid==$uuid) | .uuid) // empty
    ')
    if test -z "$primary_present"
        echo "[WARN] workspace_detect_display_mode: configured primary display is not connected: $primary_uuid" >&2
        return 1
    end

    echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" '
        (first(.[] | select(.uuid!=$uuid and .["has-focus"]==true)) // first(.[] | select(.uuid!=$uuid))) as $target
        | if $target == null then "solo"
          elif $target.frame.w > $target.frame.h then "wide"
          elif $target.frame.h > $target.frame.w then "tall"
          else "solo" end
    '
end

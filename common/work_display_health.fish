function work_display_health --description "Show read-only workspace display role health"
    set -l expected_mode $argv[1]

    switch "$expected_mode"
        case "" solo wide tall
        case "*"
            echo "[WARN] work_display_health expected mode must be one of: solo, wide, tall" >&2
            return 2
    end

    set -l displays_json (ws_yabai -m query --displays 2>/dev/null)
    if test $status -ne 0 -o -z "$displays_json"
        echo "[WARN] work_display_health could not query displays from yabai" >&2
        set displays_json "[]"
    end

    set -l primary_uuid (get_workspace_primary_display_uuid 2>/dev/null)
    set -l primary_display
    set -l target_display
    set -l secondary_count 0
    set -l target_origin_ok false
    set -l target_left_ok false
    set -l target_orientation unknown
    set -l display_count (echo $displays_json | ws_jq -r 'length')

    if test "$display_count" = "1"
        set primary_display (echo $displays_json | ws_jq -r '.[0].index // empty')
        set target_display $primary_display
        if test -z "$primary_uuid"
            set primary_uuid (echo $displays_json | ws_jq -r '.[0].uuid // empty')
        end
    else if test -n "$primary_uuid"
        set primary_display (echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" '
            first(.[] | select(.uuid==$uuid) | .index) // empty
        ')

        set secondary_count (echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" '
            map(select(.uuid!=$uuid)) | length
        ')

        if test "$expected_mode" = "wide"
            set target_display (echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" '
                first(.[] | select(.uuid!=$uuid and .frame.w > .frame.h) | .index)
                // first(.[] | select(.uuid!=$uuid) | .index)
                // empty
            ')
        else if test "$expected_mode" = "tall"
            set target_display (echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" '
                first(.[] | select(.uuid!=$uuid and .frame.h > .frame.w) | .index)
                // first(.[] | select(.uuid!=$uuid) | .index)
                // empty
            ')
        else
            set target_display (echo $displays_json | ws_jq -r --arg uuid "$primary_uuid" '
                first(.[] | select(.uuid!=$uuid) | .index) // empty
            ')
        end
    end

    if test -z "$target_display"
        set target_display $primary_display
    end

    if test -n "$target_display"
        set target_origin_ok (echo $displays_json | ws_jq -r --argjson display "$target_display" '
            first(.[] | select(.index==$display) | (.frame.x == 0 and .frame.y == 0)) // false
        ')

        set target_left_ok (echo $displays_json | ws_jq -r \
            --arg primary_uuid "$primary_uuid" \
            --argjson display "$target_display" '
            (first(.[] | select(.uuid==$primary_uuid)) // null) as $primary
            | (first(.[] | select(.index==$display)) // null) as $target
            | if $primary == null or $target == null then false
              elif $primary.uuid == $target.uuid then true
              else ($target.frame.x < $primary.frame.x)
              end
        ')

        set target_orientation (echo $displays_json | ws_jq -r --argjson display "$target_display" '
            first(.[] | select(.index==$display) | if .frame.w > .frame.h then "wide" elif .frame.h > .frame.w then "tall" else "square" end) // "unknown"
        ')
    end

    set -l dock_orientation (defaults read com.apple.dock orientation 2>/dev/null)
    set -l dock_autohide (defaults read com.apple.dock autohide 2>/dev/null)

    if test -z "$dock_orientation"
        set dock_orientation unknown
    end

    if test -z "$dock_autohide"
        set dock_autohide unknown
    end

    set -l health_json (ws_jq -n -c \
        --arg expected_mode "$expected_mode" \
        --arg primary_uuid "$primary_uuid" \
        --arg primary_display "$primary_display" \
        --arg target_display "$target_display" \
        --arg secondary_count "$secondary_count" \
        --arg display_count "$display_count" \
        --arg target_origin_ok "$target_origin_ok" \
        --arg target_left_ok "$target_left_ok" \
        --arg target_orientation "$target_orientation" \
        --arg dock_orientation "$dock_orientation" \
        --arg dock_autohide "$dock_autohide" \
        '{
            expected_mode: (if $expected_mode == "" then null else $expected_mode end),
            primary_uuid_configured: ($primary_uuid != ""),
            primary_display: (if $primary_display == "" then null else ($primary_display | tonumber) end),
            target_display: (if $target_display == "" then null else ($target_display | tonumber) end),
            secondary_count: (if $secondary_count == "" then 0 else ($secondary_count | tonumber) end),
            display_count: (if $display_count == "" then 0 else ($display_count | tonumber) end),
            target_origin_ok: ($target_origin_ok == "true"),
            target_left_ok: ($target_left_ok == "true"),
            target_orientation: $target_orientation,
            dock_orientation: $dock_orientation,
            dock_autohide: (
                if $dock_autohide == "unknown" then "unknown"
                else ($dock_autohide | tonumber)
                end
            ),
            warnings: [
                if ($display_count | tonumber) > 1 and $primary_uuid == "" then "workspace primary display UUID is not configured" else empty end,
                if ($display_count | tonumber) > 1 and $primary_uuid != "" and $primary_display == "" then "configured workspace primary display UUID is not present" else empty end,
                if $expected_mode == "solo" and ($secondary_count | tonumber) > 0 then "solo mode expected no secondary display" else empty end,
                if ($display_count | tonumber) > 1 and ($expected_mode == "wide" or $expected_mode == "tall") and $target_display != "" and $target_left_ok != "true" then "target display is not left of the workspace primary display" else empty end,
                if $expected_mode == "wide" and $target_orientation != "wide" then "wide mode expected a wide target display" else empty end,
                if $expected_mode == "tall" and $target_orientation != "tall" then "tall mode expected a tall target display" else empty end,
                if $dock_autohide != "1" then "Dock autohide is not enabled" else empty end,
                if $dock_orientation != "left" then "Dock orientation is not left" else empty end
            ],
            suggested_next_checks: [
                if ($display_count | tonumber) > 1 and $primary_uuid == "" then "detect_and_set_workspace_primary_display_uuid or set_workspace_primary_display_uuid <uuid>" else empty end,
                if $expected_mode == "solo" and ($secondary_count | tonumber) > 0 then "display_apply_solo" else empty end,
                if $expected_mode == "wide" and ($target_display == "" or $target_left_ok != "true" or $target_orientation != "wide") then "display_apply_wide_left" else empty end,
                if $expected_mode == "tall" and ($target_display == "" or $target_left_ok != "true" or $target_orientation != "tall") then "display_apply_tall_left" else empty end,
                if $dock_autohide != "1" or $dock_orientation != "left" then "check macOS Dock settings, then killall Dock if needed" else empty end
            ]
        }')

    if test $status -ne 0 -o -z "$health_json"
        echo "[WARN] work_display_health could not build display health report" >&2
        return 1
    end

    echo $health_json | ws_jq '.'

    if test -n "$expected_mode"
        set -l warning_count (echo $health_json | ws_jq -r '.warnings | length')
        if test "$warning_count" -gt 0
            return 1
        end
    end
end

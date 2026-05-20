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

    set -l internal_uuid (get_internal_display_uuid 2>/dev/null)
    set -l internal_display
    set -l external_display
    set -l external_count 0
    set -l external_origin_ok false
    set -l external_orientation unknown
    set -l display_count (echo $displays_json | ws_jq -r 'length')

    if test -n "$internal_uuid"
        set internal_display (echo $displays_json | ws_jq -r --arg uuid "$internal_uuid" '
            first(.[] | select(.uuid==$uuid) | .index) // empty
        ')

        set external_display (echo $displays_json | ws_jq -r --arg uuid "$internal_uuid" '
            first(.[] | select(.uuid!=$uuid) | .index) // empty
        ')

        set external_count (echo $displays_json | ws_jq -r --arg uuid "$internal_uuid" '
            map(select(.uuid!=$uuid)) | length
        ')

        if test -n "$external_display"
            set external_origin_ok (echo $displays_json | ws_jq -r --argjson display "$external_display" '
                first(.[] | select(.index==$display) | (.frame.x == 0 and .frame.y == 0)) // false
            ')

            set external_orientation (echo $displays_json | ws_jq -r --argjson display "$external_display" '
                first(.[] | select(.index==$display) | if .frame.w > .frame.h then "wide" elif .frame.h > .frame.w then "tall" else "square" end) // "unknown"
            ')
        end
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
        --arg internal_uuid "$internal_uuid" \
        --arg internal_display "$internal_display" \
        --arg external_display "$external_display" \
        --arg external_count "$external_count" \
        --arg display_count "$display_count" \
        --arg external_origin_ok "$external_origin_ok" \
        --arg external_orientation "$external_orientation" \
        --arg dock_orientation "$dock_orientation" \
        --arg dock_autohide "$dock_autohide" \
        '{
            expected_mode: (if $expected_mode == "" then null else $expected_mode end),
            internal_uuid_configured: ($internal_uuid != ""),
            internal_display: ($internal_display | tonumber?),
            external_display: ($external_display | tonumber?),
            external_count: ($external_count | tonumber?),
            display_count: ($display_count | tonumber?),
            external_origin_ok: ($external_origin_ok == "true"),
            external_orientation: $external_orientation,
            dock_orientation: $dock_orientation,
            dock_autohide: (
                if $dock_autohide == "unknown" then "unknown"
                else ($dock_autohide | tonumber?)
                end
            ),
            warnings: [
                if $internal_uuid == "" then "internal display UUID is not configured" else empty end,
                if $internal_uuid != "" and $internal_display == "" then "configured internal display UUID is not present" else empty end,
                if ($display_count | tonumber) > 1 and $external_display == "" then "multiple displays are visible but no external display resolved" else empty end,
                if $expected_mode == "solo" and ($external_count | tonumber) > 0 then "solo mode expected no external display" else empty end,
                if ($expected_mode == "wide" or $expected_mode == "tall") and $external_display == "" then "external mode expected an external display" else empty end,
                if $external_display != "" and $external_origin_ok != "true" then "external display is not at origin (0,0)" else empty end,
                if $expected_mode == "wide" and $external_orientation != "wide" then "wide mode expected a wide external display" else empty end,
                if $expected_mode == "tall" and $external_orientation != "tall" then "tall mode expected a tall external display" else empty end,
                if $dock_autohide != "1" then "Dock autohide is not enabled" else empty end,
                if $dock_orientation != "left" then "Dock orientation is not left" else empty end
            ],
            suggested_next_checks: [
                if $expected_mode == "solo" and ($external_count | tonumber) > 0 then "display_apply_solo" else empty end,
                if $expected_mode == "wide" and ($external_display == "" or $external_origin_ok != "true" or $external_orientation != "wide") then "display_apply_wide_left" else empty end,
                if $expected_mode == "tall" and ($external_display == "" or $external_origin_ok != "true" or $external_orientation != "tall") then "display_apply_tall_left" else empty end,
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

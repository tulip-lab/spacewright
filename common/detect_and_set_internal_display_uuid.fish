function detect_and_set_internal_display_uuid --description "Detect and set the internal display UUID using yabai as the source of truth"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Detect the internal display UUID from yabai display metadata and store
    #   it through set_internal_display_uuid.
    #
    # Source of truth:
    #   yabai display UUIDs are treated as authoritative for workspace display
    #   routing. displayplacer is not used here as the UUID authority.
    #
    # Behavior:
    #   - If there is only one display, use it directly.
    #   - If there are multiple displays, try to infer the internal display.
    #   - If inference is ambiguous, print candidate displays and return nonzero.
    #
    # Multi-display behavior:
    #   - If the configured internal UUID is still connected, keep it.
    #   - Otherwise, print all displays and ask for manual setting.
    #
    # Notes:
    #   - External-display profiles may intentionally make the external monitor
    #     the macOS primary display at origin (0, 0), so origin/focus are not safe
    #     signals for detecting the built-in display.
    #   - This function is best-effort.
    #   - It should not be treated as a hard failure path for bootstrap.
    # -------------------------------------------------------------------------

    if not command -q yabai
        echo "[WARN] yabai is not available; cannot detect internal display UUID"
        return 1
    end

    if not command -q jq
        echo "[WARN] jq is not available; cannot detect internal display UUID"
        return 1
    end

    if not functions -q set_internal_display_uuid
        echo "[WARN] set_internal_display_uuid is not available"
        return 1
    end

    set -l displays_json (ws_yabai -m query --displays 2>/dev/null)

    if test $status -ne 0 -o -z "$displays_json"
        echo "[WARN] Could not query displays from yabai"
        return 1
    end

    set -l display_count (echo $displays_json | ws_jq 'length')

    if test "$display_count" -eq 0
        echo "[WARN] No displays returned by yabai"
        return 1
    end

    # -------------------------------------------------------------------------
    # Single-display case: use it directly
    # -------------------------------------------------------------------------
    if test "$display_count" -eq 1
        set -l only_uuid (echo $displays_json | ws_jq -r '.[0].uuid')

        if test -n "$only_uuid" -a "$only_uuid" != "null"
            set_internal_display_uuid $only_uuid
            echo "[OK] Internal display UUID detected and set: $only_uuid"
            return 0
        else
            echo "[WARN] Single display found, but UUID is missing"
            return 1
        end
    end

    # -------------------------------------------------------------------------
    # Multi-display case:
    # Keep the existing configured internal UUID if it is still connected.
    # Do not infer from origin or focus. External profiles may intentionally
    # place the external display at origin (0, 0) so the Dock belongs there.
    # -------------------------------------------------------------------------
    set -l configured_uuid (get_internal_display_uuid 2>/dev/null)
    if test -n "$configured_uuid"
        set -l configured_match (echo $displays_json | ws_jq -r --arg uuid "$configured_uuid" '
            .[]
            | select(.uuid == $uuid)
            | .uuid
        ' | head -n 1)

        if test -n "$configured_match" -a "$configured_match" != "null"
            echo "[OK] Existing internal display UUID is connected: $configured_match"
            return 0
        end

        echo "[WARN] Configured internal display UUID is not currently connected: $configured_uuid"
    end

    # -------------------------------------------------------------------------
    # Ambiguous case: print candidates and ask for manual confirmation
    # -------------------------------------------------------------------------
    echo "[WARN] Could not confidently determine the internal display UUID"
    echo "[INFO] Candidate displays from yabai:"
    echo $displays_json | ws_jq -r '
        .[]
        | [
            "index=\(.index)",
            "uuid=\(.uuid)",
            "focus=\(.[\"has-focus\"])",
            "frame=(\(.frame.x),\(.frame.y),\(.frame.w),\(.frame.h))"
        ]
        | join("  ")
    '

    echo "[INFO] Please set it manually with:"
    echo "       set_internal_display_uuid <YOUR-INTERNAL-DISPLAY-UUID>"

    return 1
end

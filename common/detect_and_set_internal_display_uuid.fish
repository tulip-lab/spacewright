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
    # Inference strategy for multi-display setups:
    #   1. Prefer the display whose frame origin is (0, 0).
    #   2. If still ambiguous, prefer the focused display among candidates.
    #   3. If still ambiguous, print all displays and ask for manual setting.
    #
    # Notes:
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

    set -l displays_json (yabai -m query --displays 2>/dev/null)

    if test -z "$displays_json"
        echo "[WARN] Could not query displays from yabai"
        return 1
    end

    set -l display_count (echo $displays_json | jq 'length')

    if test "$display_count" -eq 0
        echo "[WARN] No displays returned by yabai"
        return 1
    end

    # -------------------------------------------------------------------------
    # Single-display case: use it directly
    # -------------------------------------------------------------------------
    if test "$display_count" -eq 1
        set -l only_uuid (echo $displays_json | jq -r '.[0].uuid')

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
    # Try displays whose frame origin is (0, 0)
    # -------------------------------------------------------------------------
    set -l zero_origin_matches (echo $displays_json | jq -r '
        .[]
        | select(.frame.x == 0 and .frame.y == 0)
        | .uuid
    ')

    set -l zero_origin_count (count $zero_origin_matches)

    if test "$zero_origin_count" -eq 1
        set_internal_display_uuid $zero_origin_matches[1]
        echo "[OK] Internal display UUID inferred from frame origin: $zero_origin_matches[1]"
        return 0
    end

    if test "$zero_origin_count" -gt 1
        set -l focused_zero_origin (echo $displays_json | jq -r '
            .[]
            | select(.frame.x == 0 and .frame.y == 0)
            | select(.["has-focus"] == true)
            | .uuid
        ' | head -n 1)

        if test -n "$focused_zero_origin" -a "$focused_zero_origin" != "null"
            set_internal_display_uuid $focused_zero_origin
            echo "[OK] Internal display UUID inferred from zero-origin focused display: $focused_zero_origin"
            return 0
        end
    end

    # -------------------------------------------------------------------------
    # Fallback:
    # If there is exactly one focused display and no better rule worked,
    # use it as a best-effort guess.
    # -------------------------------------------------------------------------
    set -l focused_matches (echo $displays_json | jq -r '
        .[]
        | select(.["has-focus"] == true)
        | .uuid
    ')

    if test (count $focused_matches) -eq 1
        set_internal_display_uuid $focused_matches[1]
        echo "[OK] Internal display UUID inferred from focused display: $focused_matches[1]"
        return 0
    end

    # -------------------------------------------------------------------------
    # Ambiguous case: print candidates and ask for manual confirmation
    # -------------------------------------------------------------------------
    echo "[WARN] Could not confidently determine the internal display UUID"
    echo "[INFO] Candidate displays from yabai:"
    echo $displays_json | jq -r '
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
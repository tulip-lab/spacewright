function display_verify_mode --description "Wait briefly and verify the current display role for a workspace mode"
    set -l expected_mode $argv[1]

    switch "$expected_mode"
        case solo wide tall
        case "*"
            echo "[WARN] display_verify_mode expected mode must be one of: solo, wide, tall" >&2
            return 2
    end

    set -l settle_seconds 0.8
    if set -q WORKSPACE_DISPLAY_SETTLE_SECONDS
        set settle_seconds $WORKSPACE_DISPLAY_SETTLE_SECONDS
    end

    if not string match -qr '^[0-9]+([.][0-9]+)?$' -- "$settle_seconds"
        echo "[WARN] display_verify_mode ignored invalid WORKSPACE_DISPLAY_SETTLE_SECONDS=$settle_seconds" >&2
        set settle_seconds 0.8
    end

    sleep $settle_seconds
    work_display_health $expected_mode
end

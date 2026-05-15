function work_bad_windows --description "Show cached bad yabai window IDs"
    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l bad_window_ttl "$WORKSPACE_BAD_WINDOW_TTL_SECONDS"

    if test -z "$bad_window_ttl"
        set bad_window_ttl 600
    end

    echo "===== BAD WINDOW CACHE ====="

    if not test -d "$bad_window_dir"
        echo "none"
        return 0
    end

    set -l bad_files (find "$bad_window_dir" -type f 2>/dev/null)
    if test (count $bad_files) -eq 0
        echo "none"
        return 0
    end

    set -l windows_json (yabai -m query --windows 2>/dev/null)
    set -l live_window_ids (echo $windows_json | jq -r '.[].id')
    set -l now (date +%s)
    set -l count 0

    for file in $bad_files
        set -l window_id (basename "$file")
        set -l bad_at (cat "$file" 2>/dev/null)

        if not string match -qr '^[0-9]+$' -- "$window_id"
            continue
        end

        if not string match -qr '^[0-9]+$' -- "$bad_at"
            continue
        end

        set count (math $count + 1)
        set -l age (math $now - $bad_at)
        set -l state active
        set -l present false

        if test "$age" -ge "$bad_window_ttl"
            set state expired
        end

        if contains -- "$window_id" $live_window_ids
            set present true
        end

        printf "window=%s age=%ss state=%s present_in_yabai=%s\n" "$window_id" "$age" "$state" "$present"
    end

    if test "$count" -eq 0
        echo "none"
    end
end

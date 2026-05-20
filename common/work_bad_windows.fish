function work_bad_windows --description "Show cached bad yabai window IDs"
    argparse h/help all summary active expired present missing -- $argv
    or return 2

    if set -q _flag_help
        echo "usage: work_bad_windows [--summary] [--all] [--active] [--expired] [--present] [--missing]"
        return 0
    end

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

    set -l windows_json (ws_yabai -m query --windows 2>/dev/null)
    if test $status -ne 0 -o -z "$windows_json"
        echo "[WARN] work_bad_windows could not query windows from yabai" >&2
        set windows_json "[]"
    end

    set -l live_window_ids (echo $windows_json | ws_jq -r '.[].id')
    set -l now (date +%s)
    set -l count 0
    set -l filtered_count 0
    set -l active_count 0
    set -l expired_count 0
    set -l present_count 0
    set -l missing_count 0
    set -l lines

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

        if test "$state" = active
            set active_count (math $active_count + 1)
        else
            set expired_count (math $expired_count + 1)
        end

        if test "$present" = true
            set present_count (math $present_count + 1)
        else
            set missing_count (math $missing_count + 1)
        end

        set -l include true

        if set -q _flag_active; and not set -q _flag_expired
            if test "$state" != active
                set include false
            end
        else if set -q _flag_expired; and not set -q _flag_active
            if test "$state" != expired
                set include false
            end
        end

        if set -q _flag_present; and not set -q _flag_missing
            if test "$present" != true
                set include false
            end
        else if set -q _flag_missing; and not set -q _flag_present
            if test "$present" != false
                set include false
            end
        end

        if test "$include" = true
            set filtered_count (math $filtered_count + 1)
            set -a lines (printf "window=%s age=%ss state=%s present_in_yabai=%s" "$window_id" "$age" "$state" "$present")
        end
    end

    if test "$count" -eq 0
        echo "none"
        return 0
    end

    if set -q _flag_summary
        printf "total=%s active=%s expired=%s present_in_yabai=%s missing_from_yabai=%s ttl=%ss\n" \
            "$count" "$active_count" "$expired_count" "$present_count" "$missing_count" "$bad_window_ttl"
        return 0
    end

    if test "$filtered_count" -eq 0
        echo "none"
        return 0
    end

    printf "%s\n" $lines
end

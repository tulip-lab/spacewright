function work_clear_bad_windows --description "Clear cached bad yabai window IDs"
    argparse h/help all active expired present missing -- $argv
    or return 2

    if set -q _flag_help
        echo "usage: work_clear_bad_windows [--all] [--active] [--expired] [--present] [--missing]"
        return 0
    end

    set -l bad_window_dir /tmp/workspace-ws-window-bad
    set -l bad_window_ttl "$WORKSPACE_BAD_WINDOW_TTL_SECONDS"

    if test -z "$bad_window_ttl"
        set bad_window_ttl 600
    end

    if not test -d "$bad_window_dir"
        echo "Bad window cache is already empty"
        return 0
    end

    if set -q _flag_all; or begin
            not set -q _flag_active
            and not set -q _flag_expired
            and not set -q _flag_present
            and not set -q _flag_missing
        end
        rm -rf "$bad_window_dir"
        echo "Cleared bad window cache: $bad_window_dir"
        return 0
    end

    set -l bad_files (find "$bad_window_dir" -type f 2>/dev/null)
    if test (count $bad_files) -eq 0
        echo "Bad window cache is already empty"
        return 0
    end

    set -l windows_json (ws_yabai -m query --windows 2>/dev/null)
    if test $status -ne 0 -o -z "$windows_json"
        echo "[WARN] work_clear_bad_windows could not query windows from yabai" >&2
        set windows_json "[]"
    end

    set -l live_window_ids (echo $windows_json | ws_jq -r '.[].id')
    set -l now (date +%s)
    set -l cleared_count 0

    for file in $bad_files
        set -l window_id (basename "$file")
        set -l bad_at (cat "$file" 2>/dev/null)

        if not string match -qr '^[0-9]+$' -- "$window_id"
            continue
        end

        if not string match -qr '^[0-9]+$' -- "$bad_at"
            continue
        end

        set -l age (math $now - $bad_at)
        set -l state active
        set -l present false

        if test "$age" -ge "$bad_window_ttl"
            set state expired
        end

        if contains -- "$window_id" $live_window_ids
            set present true
        end

        set -l clear false

        if set -q _flag_active; and test "$state" = active
            set clear true
        end

        if set -q _flag_expired; and test "$state" = expired
            set clear true
        end

        if set -q _flag_present; and test "$present" = true
            set clear true
        end

        if set -q _flag_missing; and test "$present" = false
            set clear true
        end

        if test "$clear" = true
            rm -f "$file" 2>/dev/null
            set cleared_count (math $cleared_count + 1)
        end
    end

    printf "Cleared bad window cache entries: %s\n" "$cleared_count"
end

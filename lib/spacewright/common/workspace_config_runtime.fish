function workspace_run_configured --description "Run one validated configured workspace"
    argparse dry-run -- $argv
    or return 1

    set -l workspace_id $argv[1]
    if test -z "$workspace_id"
        echo "usage: workspace_run_configured <workspace> [--dry-run]" >&2
        return 2
    end

    set -l plan (workspace_config_plan "$workspace_id" | string collect)
    or return 1

    set -l runner (printf "%s\n" "$plan" | jq -r '.runner')
    if test "$runner" != primary_helper
        echo "[WARN] $workspace_id uses unsupported configured runner: $runner" >&2
        return 1
    end

    set -l primary_count (printf "%s\n" "$plan" | jq '[.windows[] | select(.role == "primary" and .required == true)] | length')
    set -l helper_count (printf "%s\n" "$plan" | jq '[.windows[] | select(.role == "helper" and .required == false)] | length')
    if test "$primary_count" -ne 1; or test "$helper_count" -gt 1
        echo "[WARN] $workspace_id primary_helper requires one required primary and at most one optional helper" >&2
        return 1
    end

    set -l label (printf "%s\n" "$plan" | jq -r '.label')
    set -l display_role (printf "%s\n" "$plan" | jq -r '.display_role')
    set -l space_layout (printf "%s\n" "$plan" | jq -r '.space_layout')
    set -l primary_app_key (printf "%s\n" "$plan" | jq -r '.windows[] | select(.role == "primary" and .required == true) | .app_key')
    set -l helper_app_key (printf "%s\n" "$plan" | jq -r 'first(.windows[] | select(.role == "helper" and .required == false) | .app_key) // empty')
    set -l primary_grid (printf "%s\n" "$plan" | jq -r '.layout[] | select(.role == "primary") | .grid // empty')
    set -l helper_grid (printf "%s\n" "$plan" | jq -r 'first(.layout[] | select(.role == "helper") | .grid) // empty')
    set -l primary_alone_grid (printf "%s\n" "$plan" | jq -r 'first(.primary_alone_layout[]? | select(.role == "primary") | .grid) // empty')

    if test -z "$primary_grid"
        echo "[WARN] $workspace_id primary_helper requires a primary grid action" >&2
        return 1
    end

    set -l apply_args \
        --label "$label" \
        --caller "$workspace_id" \
        --display "$display_role" \
        --layout "$space_layout" \
        --primary-app-key "$primary_app_key" \
        --primary-grid "$primary_grid"

    if test -n "$primary_alone_grid"
        set -a apply_args --primary-alone-grid "$primary_alone_grid"
    end

    if test -n "$helper_app_key"
        if test -z "$helper_grid"
            echo "[WARN] $workspace_id helper requires a helper grid action" >&2
            return 1
        end
        set -a apply_args --helper-app-key "$helper_app_key" --helper-grid "$helper_grid"
    end

    set -l cleanup_specs (printf "%s\n" "$plan" | jq -r '.cleanup as $cleanup | if $cleanup then $cleanup.opposite_modes[] | $cleanup.family + ":" + . else empty end')
    set -a apply_args $cleanup_specs

    if set -q _flag_dry_run
        workspace_apply_primary_helper_space $apply_args --dry-run
        return $status
    end

    set -l required_window (workspace_find_app_key_window \
        --app-key "$primary_app_key" \
        --caller "$workspace_id-config-preflight")
    set -l preflight_status $status
    if test "$preflight_status" -ne 0; or test -z "$required_window"
        echo "[WARN] $workspace_id required app is unavailable; no workspace changes were made" >&2
        return 1
    end

    workspace_apply_primary_helper_space $apply_args
end

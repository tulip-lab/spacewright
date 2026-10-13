function display_reload --description "Reload display workspace functions"
    source "$SPACEWRIGHT_ROOT/display/display_entries.fish"
end

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

function display_apply_profile_mode --description "Apply a display profile, reload workspace functions, and verify mode"
    if contains -- --dry-run $argv
        printf 'dry_run=display_apply_profile_mode\n'
        return 0
    end
    if test -n "$SPACEWRIGHT_PACKAGE_ROOT"; and not contains -- --dry-run $argv
        if not workspace_execution_owned 2>/dev/null
            command node "$SPACEWRIGHT_PACKAGE_ROOT/configurator/execution-cli.mjs" exec fish --no-config -c 'source "$SPACEWRIGHT_PACKAGE_ROOT/conf.d/spacewright.fish"; $argv' -- display_apply_profile_mode $argv
            return $status
        end
    end
    set -l profile_command $argv[1]
    set -l mode $argv[2]

    if test -z "$profile_command" -o -z "$mode"
        echo "usage: display_apply_profile_mode <profile-command> <solo|wide|tall>" >&2
        return 2
    end

    $profile_command
    or return $status

    display_reload
    or return $status

    work_reload
    or return $status

    display_verify_mode $mode
end

function display_apply_solo --description "Apply solo primary-display layout and reload display/workspace functions"
    display_apply_profile_mode "$SPACEWRIGHT_DISPLAY_PROFILES_ROOT/display-solo-primary.fish" solo $argv
end

function display_apply_wide_left --description "Apply wide-left display layout and reload display/workspace functions"
    display_apply_profile_mode "$SPACEWRIGHT_DISPLAY_PROFILES_ROOT/display-primary-plus-wide-left.fish" wide $argv
end

function display_apply_tall_left --description "Apply tall-left display layout and reload display/workspace functions"
    display_apply_profile_mode "$SPACEWRIGHT_DISPLAY_PROFILES_ROOT/display-primary-plus-tall-left.fish" tall $argv
end

#!/usr/bin/env fish

set -l test_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $test_file))
set -l test_root (mktemp -d /private/tmp/spacewright-config-test.XXXXXX)

set -gx SPACEWRIGHT_CONFIG_ROOT "$test_root/config"
mkdir -p "$SPACEWRIGHT_CONFIG_ROOT"
source "$package_root/conf.d/spacewright.fish"

workspace_config_check
or exit 1

set -l plan (workspace_config_plan coding_editor_wide | string collect)
or exit 2
printf "%s\n" "$plan" | jq -e '
    .kind == "workspace"
    and .mutates == false
    and .display_role == "wide"
    and (.windows | length) == 2
' >/dev/null
or exit 3

set -l configured_dry_run (workspace_run_configured coding_editor_wide --dry-run | string collect)
or exit 4
set -l legacy_dry_run (__coding_editor_wide_legacy_body --dry-run | string collect)
or exit 5
test "$configured_dry_run" = "$legacy_dry_run"
or exit 6

set -g __spacewright_config_apply_calls 0
function workspace_find_app_key_window
    echo 42
end
function workspace_apply_primary_helper_space
    set -g __spacewright_config_apply_calls (math $__spacewright_config_apply_calls + 1)
end
workspace_run_configured coding_editor_wide
or exit 7
test $__spacewright_config_apply_calls -eq 1
or exit 8

function workspace_find_app_key_window
    return 2
end
set -g __spacewright_config_apply_calls 0
if workspace_run_configured coding_editor_wide >/dev/null 2>&1
    exit 9
end
test $__spacewright_config_apply_calls -eq 0
or exit 10

printf '%s\n' '{"version":1,"apps":{"code":{"names":["Custom Code"]}}}' > "$SPACEWRIGHT_CONFIG_ROOT/config.json"
workspace_config_check
or exit 11

set -l configured_names (spacewright_config_effective | jq -r '.apps.code.names[]')
test "$configured_names" = "Custom Code"
or exit 12
test (workspace_app_name code) = "Custom Code"
or exit 13

printf '%s\n' '{"version":2}' > "$SPACEWRIGHT_CONFIG_ROOT/config.json"
if workspace_config_check >/dev/null 2>&1
    exit 14
end

echo "OK      config validation, override, runtime parity, and fail-closed preflight"

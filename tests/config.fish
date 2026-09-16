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

printf '%s\n' '{"version":1,"apps":{"code":{"names":["Custom Code"]}}}' > "$SPACEWRIGHT_CONFIG_ROOT/config.json"
workspace_config_check
or exit 4

set -l configured_names (spacewright_config_effective | jq -r '.apps.code.names[]')
test "$configured_names" = "Custom Code"
or exit 5

printf '%s\n' '{"version":2}' > "$SPACEWRIGHT_CONFIG_ROOT/config.json"
if workspace_config_check >/dev/null 2>&1
    exit 6
end

echo "OK      config validation, override, and read-only plan"

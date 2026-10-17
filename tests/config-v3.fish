#!/usr/bin/env fish

set -l test_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $test_file))
set -l test_root (mktemp -d /private/tmp/spacewright-config-v3-test.XXXXXX)
set -l config_root "$test_root/config"
set -l state_root "$test_root/state"
mkdir -p "$config_root" "$state_root"

command node "$package_root/configurator/cli.mjs" starter-v3 > "$config_root/config.v3.json"
or exit 1
printf '%s\n' '{"unavailable":false,"displays":[{"index":1,"uuid":"DISPLAY-TALL-1234","frame":{"x":0,"y":0,"w":1200,"h":1920},"is-built-in":false}]}' > "$test_root/displays.json"

command node "$package_root/configurator/setup-cli.mjs" confirm mac_mini single_tall \
    "--config-root=$config_root" \
    "--state-root=$state_root" \
    "--snapshot=$test_root/displays.json" \
    --model=Macmini9,1 >/dev/null
or exit 2

set -l fake_bin "$test_root/bin"
mkdir -p "$fake_bin"
printf '%s\n' '#!/bin/sh' 'printf "%s\n" "Macmini9,1"' > "$fake_bin/sysctl"
printf '%s\n' '#!/bin/sh' 'case "$3" in' \
    '  --displays) printf "%s\n" '\''[{"index":1,"uuid":"DISPLAY-TALL-1234","frame":{"x":0,"y":0,"w":1200,"h":1920},"is-built-in":false}]'\'' ;;' \
    '  --spaces) printf "%s\n" '\''[{"index":1,"uuid":"SPACE-TALL-1234","display":1,"label":"","windows":[],"has-focus":true}]'\'' ;;' \
    '  --windows) printf "%s\n" '\''[]'\'' ;;' \
    '  *) exit 2 ;;' \
    'esac' > "$fake_bin/yabai"
chmod +x "$fake_bin/sysctl" "$fake_bin/yabai"
set -gx PATH "$fake_bin" $PATH
set -gx SPACEWRIGHT_CONFIG_ROOT "$config_root"
set -gx SPACEWRIGHT_STATE_ROOT "$state_root"
source "$package_root/conf.d/spacewright.fish"
or exit 3

spacewright_config_status | jq -e '.version == 3 and .current == true' >/dev/null
or exit 4
spacewright_config_effective | jq -e '
    .source_version == 3
    and .active_hardware_profile == "mac_mini"
    and .active_setup == "single_tall"
    and .workspace_configurations.coding == "tall"
    and .workspaces.spacewright_coding_tall.ui.workspace_id == "coding"
    and .workspaces.spacewright_coding_tall.ui.mode == "tall"
' >/dev/null
or exit 5
workspace_config_check
or exit 6
workspace_config_plan spacewright_coding_tall | jq -e '.label == "coding_tall" and .display_role == "tall__tall"' >/dev/null
or exit 7

command cp "$state_root/machine.json" "$test_root/machine.before.json"
command cp "$config_root/generated/runtime.json" "$test_root/runtime.before.json"
env PATH="$fake_bin:$PATH" "$package_root/bin/spacewright" workspace coding --dry-run --json > "$test_root/workspace-preview.json"
# This fixture has no editor window: the full read-only plan must report the
# missing required window rather than the old unconditional transition stub.
test $status -eq 1
or exit 8
jq -e '.dryRun == true and .mutates == false and .plan.target.mode == "tall" and .plan.scope == "workspace" and .plan.executable == false' "$test_root/workspace-preview.json" >/dev/null
or exit 8
command cmp -s "$test_root/machine.before.json" "$state_root/machine.json"
or exit 9
command cmp -s "$test_root/runtime.before.json" "$config_root/generated/runtime.json"
or exit 10

set -l doctor_output (work_doctor 2>&1)
string match -q '*OK      SpaceWright configuration v3 and compiled runtime*' -- $doctor_output
or exit 11
not string match -q '*compiled runtime is missing or stale*' -- $doctor_output
or exit 12

echo "OK      v3 hardware setup, compiled runtime freshness, and Fish planning"

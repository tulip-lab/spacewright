#!/usr/bin/env fish

set -l test_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $test_file))
set -l test_root (mktemp -d /private/tmp/spacewright-install-test.XXXXXX)
set -l install_root "$test_root/package"
set -l fish_root "$test_root/fish"
set -l bin_root "$test_root/bin"
set -l installed_release_root "$install_root/releases/"(string trim < "$package_root/VERSION")

fish "$package_root/scripts/install.fish" \
    --source-root "$package_root" \
    --prefix "$install_root" \
    --fish-config-root "$fish_root" \
    --bin-root "$bin_root" >/dev/null
or exit 1

test -L "$install_root/current"
or exit 2
test -L "$fish_root/conf.d/spacewright.fish"
or exit 3
test -L "$bin_root/spacewright"
or exit 4
test ("$bin_root/spacewright" version) = (string trim < "$package_root/VERSION")
or exit 5
"$bin_root/spacewright" version >/dev/null
or exit 19
for configurator_file in \
        server.mjs \
        cli.mjs \
        lib/config-v2.mjs \
        lib/transition-history.mjs \
        public/index.html \
        public/app.js \
        public/styles.css
    test -f "$installed_release_root/configurator/$configurator_file"
    or exit 15
end
test -f "$installed_release_root/node_modules/yaml/package.json"
or exit 20
test -x "$installed_release_root/bin/spacewright-banner"
or exit 25
test -f "$installed_release_root/configurator/mode-transition.mjs"
or exit 26
node --check "$installed_release_root/configurator/server.mjs"
or exit 16
node --check "$installed_release_root/configurator/public/app.js"
or exit 18
node "$installed_release_root/configurator/cli.mjs" starter | jq -e '.version == 2 and (.modes | keys == ["solo", "tall", "wide"])' >/dev/null
or exit 17
"$bin_root/spacewright" mode wide --dry-run | string match -q '*policy=latest_request_wins*'
or exit 27
set -l workspace_dry_run (env \
    -u SPACEWRIGHT_PACKAGE_ROOT -u SPACEWRIGHT_ROOT -u SPACEWRIGHT_CONFIG_ROOT \
    -u SPACEWRIGHT_STATE_ROOT -u SPACEWRIGHT_DISPLAY_PROFILES_ROOT \
    -u SPACEWRIGHT_SKHD_ROOT -u SPACEWRIGHT_YABAI_ROOT \
    HOME="$test_root" XDG_CONFIG_HOME="$test_root/xdg" \
    "$bin_root/spacewright" workspace gtd_ai solo --dry-run | string collect)
string match -q '*scope=target_only*' -- "$workspace_dry_run"
    and string match -q '*finalization=none*' -- "$workspace_dry_run"
or exit 28
env \
    -u SPACEWRIGHT_PACKAGE_ROOT -u SPACEWRIGHT_ROOT -u SPACEWRIGHT_CONFIG_ROOT \
    -u SPACEWRIGHT_STATE_ROOT -u SPACEWRIGHT_DISPLAY_PROFILES_ROOT \
    -u SPACEWRIGHT_SKHD_ROOT -u SPACEWRIGHT_YABAI_ROOT \
    HOME="$test_root" XDG_CONFIG_HOME="$test_root/xdg" \
    "$bin_root/spacewright" transition-history | jq -e '.transitions == []' >/dev/null
or exit 29

set -l server_log "$test_root/configurator.log"
env HOME="$test_root" node "$installed_release_root/configurator/server.mjs" \
    "--package-root=$installed_release_root" \
    "--config-root=$test_root/server-config" \
    "--state-root=$test_root/server-state" \
    --port=0 --no-open >"$server_log" 2>&1 &
set -l server_pid $last_pid
for attempt in (seq 1 30)
    if grep -q 'SPACEWRIGHT_CONFIGURATOR_URL=' "$server_log"
        break
    end
    sleep 0.1
end
grep -q 'SPACEWRIGHT_CONFIGURATOR_URL=' "$server_log"
or begin
    command kill "$server_pid" 2>/dev/null
    exit 21
end
command kill "$server_pid"
wait "$server_pid"

env \
    -u SPACEWRIGHT_PACKAGE_ROOT -u SPACEWRIGHT_ROOT -u SPACEWRIGHT_CONFIG_ROOT \
    -u SPACEWRIGHT_STATE_ROOT -u SPACEWRIGHT_DISPLAY_PROFILES_ROOT \
    -u SPACEWRIGHT_SKHD_ROOT -u SPACEWRIGHT_YABAI_ROOT \
    HOME="$test_root" XDG_CONFIG_HOME="$test_root/xdg" fish --no-config -c \
    "source '$fish_root/conf.d/spacewright.fish'; test \"\$SPACEWRIGHT_PACKAGE_ROOT\" = '$installed_release_root'"
or exit 6
env \
    -u SPACEWRIGHT_PACKAGE_ROOT -u SPACEWRIGHT_ROOT -u SPACEWRIGHT_CONFIG_ROOT \
    -u SPACEWRIGHT_STATE_ROOT -u SPACEWRIGHT_DISPLAY_PROFILES_ROOT \
    -u SPACEWRIGHT_SKHD_ROOT -u SPACEWRIGHT_YABAI_ROOT \
    HOME="$test_root" XDG_CONFIG_HOME="$test_root/xdg" fish --no-config -c \
    "set -gx SPACEWRIGHT_USE_LEGACY 1; source '$fish_root/conf.d/spacewright.fish'; not set -q SPACEWRIGHT_ROOT"
or exit 7

set -l smoke_log "$test_root/work-smoke.log"
env \
    -u SPACEWRIGHT_PACKAGE_ROOT -u SPACEWRIGHT_ROOT -u SPACEWRIGHT_CONFIG_ROOT \
    -u SPACEWRIGHT_STATE_ROOT -u SPACEWRIGHT_DISPLAY_PROFILES_ROOT \
    -u SPACEWRIGHT_SKHD_ROOT -u SPACEWRIGHT_YABAI_ROOT \
    HOME="$test_root" XDG_CONFIG_HOME="$test_root/xdg" fish --no-config -c \
    "source '$fish_root/conf.d/spacewright.fish'; work_smoke" >"$smoke_log" 2>&1
set -l smoke_status $status
if test "$smoke_status" -ne 0
    printf "FAIL    installed work_smoke status=%s log=%s\n" "$smoke_status" "$smoke_log" >&2
    cat "$smoke_log" >&2
    exit 8
end

fish "$package_root/scripts/install.fish" \
    --source-root "$package_root" \
    --prefix "$install_root" \
    --fish-config-root "$fish_root" \
    --bin-root "$bin_root" >/dev/null
or exit 9

set -l development_version 0.0.0-dev.install-test
fish "$package_root/scripts/install.fish" \
    --source-root "$package_root" \
    --prefix "$install_root" \
    --fish-config-root "$fish_root" \
    --bin-root "$bin_root" \
    --version "$development_version" >/dev/null
or exit 22
test ("$bin_root/spacewright" version) = "$development_version"
or exit 23
test (path basename (readlink "$install_root/current")) = "$development_version"
or exit 24

set -l user_config_root "$test_root/user-config/spacewright"
mkdir -p "$user_config_root"
printf '%s\n' '{"version":1}' > "$user_config_root/config.json"

fish "$package_root/scripts/uninstall.fish" \
    --prefix "$install_root" \
    --fish-config-root "$fish_root" \
    --bin-root "$bin_root" >/dev/null
or exit 10

not test -e "$install_root"
or exit 11
not test -e "$fish_root/conf.d/spacewright.fish"
or exit 12
not test -e "$bin_root/spacewright"
or exit 13
test -e "$user_config_root/config.json"
or exit 14

echo "OK      idempotent install and config-preserving uninstall"

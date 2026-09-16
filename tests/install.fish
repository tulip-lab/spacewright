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

env -u SPACEWRIGHT_PACKAGE_ROOT -u SPACEWRIGHT_ROOT -u SPACEWRIGHT_CONFIG_ROOT \
    HOME="$test_root" XDG_CONFIG_HOME="$test_root/xdg" fish --no-config -c \
    "source '$fish_root/conf.d/spacewright.fish'; test \"\$SPACEWRIGHT_PACKAGE_ROOT\" = '$installed_release_root'"
or exit 6
env -u SPACEWRIGHT_PACKAGE_ROOT -u SPACEWRIGHT_ROOT -u SPACEWRIGHT_CONFIG_ROOT \
    HOME="$test_root" XDG_CONFIG_HOME="$test_root/xdg" fish --no-config -c \
    "set -gx SPACEWRIGHT_USE_LEGACY 1; source '$fish_root/conf.d/spacewright.fish'; not set -q SPACEWRIGHT_ROOT"
or exit 7

fish "$package_root/scripts/install.fish" \
    --source-root "$package_root" \
    --prefix "$install_root" \
    --fish-config-root "$fish_root" \
    --bin-root "$bin_root" >/dev/null
or exit 8

set -l user_config_root "$test_root/user-config/spacewright"
mkdir -p "$user_config_root"
printf '%s\n' '{"version":1}' > "$user_config_root/config.json"

fish "$package_root/scripts/uninstall.fish" \
    --prefix "$install_root" \
    --fish-config-root "$fish_root" \
    --bin-root "$bin_root" >/dev/null
or exit 9

not test -e "$install_root"
or exit 10
not test -e "$fish_root/conf.d/spacewright.fish"
or exit 11
not test -e "$bin_root/spacewright"
or exit 12
test -e "$user_config_root/config.json"
or exit 13

echo "OK      idempotent install and config-preserving uninstall"

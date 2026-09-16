#!/usr/bin/env fish

set -l test_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $test_file))
set -l test_root (mktemp -d /private/tmp/spacewright-install-test.XXXXXX)
set -l install_root "$test_root/package"
set -l fish_root "$test_root/fish"
set -l bin_root "$test_root/bin"

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

fish "$package_root/scripts/install.fish" \
    --source-root "$package_root" \
    --prefix "$install_root" \
    --fish-config-root "$fish_root" \
    --bin-root "$bin_root" >/dev/null
or exit 6

set -l user_config_root "$test_root/user-config/spacewright"
mkdir -p "$user_config_root"
printf '%s\n' '{"version":1}' > "$user_config_root/config.json"

fish "$package_root/scripts/uninstall.fish" \
    --prefix "$install_root" \
    --fish-config-root "$fish_root" \
    --bin-root "$bin_root" >/dev/null
or exit 7

not test -e "$install_root"
or exit 8
not test -e "$fish_root/conf.d/spacewright.fish"
or exit 9
not test -e "$bin_root/spacewright"
or exit 10
test -e "$user_config_root/config.json"
or exit 11

echo "OK      idempotent install and config-preserving uninstall"

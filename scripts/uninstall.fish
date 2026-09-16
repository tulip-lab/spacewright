#!/usr/bin/env fish

argparse 'prefix=' 'fish-config-root=' 'bin-root=' dry-run keep-packages -- $argv
or exit 2

set -l prefix "$HOME/.local/share/spacewright"
set -q _flag_prefix; and set prefix (string trim --right --chars=/ $_flag_prefix)

set -l fish_config_root "$HOME/.config/fish"
if set -q XDG_CONFIG_HOME; and test -n "$XDG_CONFIG_HOME"
    set fish_config_root "$XDG_CONFIG_HOME/fish"
end
set -q _flag_fish_config_root; and set fish_config_root (string trim --right --chars=/ $_flag_fish_config_root)

set -l bin_root "$HOME/.local/bin"
set -q _flag_bin_root; and set bin_root (string trim --right --chars=/ $_flag_bin_root)

if test -z "$prefix"; or test "$prefix" = /; or test "$prefix" = "$HOME"
    echo "spacewright uninstall: unsafe install prefix: $prefix" >&2
    exit 2
end

set -l bootstrap_link "$fish_config_root/conf.d/spacewright.fish"
set -l cli_link "$bin_root/spacewright"
if set -q _flag_dry_run
    set -l package_removal true
    set -q _flag_keep_packages; and set package_removal false
    set -l config_root "$HOME/.config/spacewright"
    if set -q XDG_CONFIG_HOME; and test -n "$XDG_CONFIG_HOME"
        set config_root "$XDG_CONFIG_HOME/spacewright"
    end
    printf 'remove_bootstrap=%s\nremove_cli=%s\nremove_packages=%s\npreserve_config=%s\n' \
        "$bootstrap_link" \
        "$cli_link" \
        "$package_removal" \
        "$config_root"
    exit 0
end

if test -L "$bootstrap_link"
    set -l bootstrap_target (readlink "$bootstrap_link")
    if string match -q "$prefix/*" -- "$bootstrap_target"
        command rm "$bootstrap_link"
    else
        echo "spacewright uninstall: preserving unmanaged symlink $bootstrap_link" >&2
    end
end

if test -L "$cli_link"
    set -l cli_target (readlink "$cli_link")
    if string match -q "$prefix/*" -- "$cli_target"
        command rm "$cli_link"
    else
        echo "spacewright uninstall: preserving unmanaged symlink $cli_link" >&2
    end
end

if set -q _flag_keep_packages
    test -L "$prefix/current"; and command rm "$prefix/current"
else if test -e "$prefix/.spacewright-install-root"; and test (string trim < "$prefix/.spacewright-install-root") = spacewright-install-root-v1
    command rm -rf "$prefix"
else if test -e "$prefix"
    echo "spacewright uninstall: refusing to remove unrecognized prefix $prefix" >&2
    exit 1
end

echo "uninstalled SpaceWright; user configuration was preserved"

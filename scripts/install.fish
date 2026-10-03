#!/usr/bin/env fish

argparse 'prefix=' 'fish-config-root=' 'bin-root=' 'source-root=' 'version=' dry-run -- $argv
or exit 2

set -l script_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $script_file))
set -l source_root $package_root
set -q _flag_source_root; and set source_root (path resolve $_flag_source_root)

set -l package_version (string trim < "$source_root/VERSION")
set -q _flag_version; and set package_version $_flag_version
if not string match -qr '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$' -- "$package_version"
    echo "spacewright install: invalid version: $package_version" >&2
    exit 2
end

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
    echo "spacewright install: unsafe install prefix: $prefix" >&2
    exit 2
end

set -l release_root "$prefix/releases/$package_version"
set -l current_link "$prefix/current"
set -l bootstrap_link "$fish_config_root/conf.d/spacewright.fish"
set -l cli_link "$bin_root/spacewright"

if set -q _flag_dry_run
    printf 'release=%s\ncurrent=%s\nfish_bootstrap=%s\ncli=%s\n' "$release_root" "$current_link" "$bootstrap_link" "$cli_link"
    exit 0
end

for required in lib config schemas conf.d bin configurator package.json package-lock.json VERSION LICENSE README.md
    if not test -e "$source_root/$required"
        echo "spacewright install: source is missing $required" >&2
        exit 1
    end
end

command mkdir -p "$prefix/releases" "$fish_config_root/conf.d" "$bin_root"
printf '%s\n' spacewright-install-root-v1 > "$prefix/.spacewright-install-root"

if test -e "$release_root"
    if not test -f "$release_root/.spacewright-release"; or test (string trim < "$release_root/.spacewright-release") != "$package_version"
        echo "spacewright install: refusing to reuse unrecognized release $release_root" >&2
        exit 1
    end
else
    set -l staging_root "$prefix/.staging-$fish_pid-$package_version"
    command rm -rf "$staging_root"
    command mkdir -p "$staging_root"
    or exit 1

    for item in lib config schemas conf.d bin configurator package.json package-lock.json VERSION LICENSE README.md CHANGELOG.md SECURITY.md
        if test -e "$source_root/$item"
            command cp -R "$source_root/$item" "$staging_root/"
            or begin
                command rm -rf "$staging_root"
                exit 1
            end
        end
    end

    if test -d "$source_root/node_modules/yaml"
        command mkdir -p "$staging_root/node_modules"
        command cp -R "$source_root/node_modules/yaml" "$staging_root/node_modules/"
        or begin
            command rm -rf "$staging_root"
            exit 1
        end
    else
        if not command -q npm
            echo 'spacewright install: npm is required when production dependencies are not present in the source tree' >&2
            command rm -rf "$staging_root"
            exit 1
        end
        command npm ci --omit=dev --ignore-scripts --prefix "$staging_root"
        or begin
            command rm -rf "$staging_root"
            exit 1
        end
    end

    # --version names the immutable installed artifact, so its reported version
    # must match the release directory even for local development builds.
    printf '%s\n' "$package_version" > "$staging_root/VERSION"
    printf '%s\n' "$package_version" > "$staging_root/.spacewright-release"
    command mv "$staging_root" "$release_root"
    or exit 1
end

if test -e "$current_link"; and not test -L "$current_link"
    echo "spacewright install: refusing to replace non-symlink $current_link" >&2
    exit 1
end
command ln -sfn "$release_root" "$current_link"
or exit 1

if test -e "$bootstrap_link"; or test -L "$bootstrap_link"
    if not test -L "$bootstrap_link"
        echo "spacewright install: refusing to replace non-symlink $bootstrap_link" >&2
        exit 1
    end
    set -l existing_target (readlink "$bootstrap_link")
    if not string match -q "$prefix/*" -- "$existing_target"
        echo "spacewright install: refusing to replace unmanaged symlink $bootstrap_link" >&2
        exit 1
    end
end
command ln -sfn "$current_link/conf.d/spacewright.fish" "$bootstrap_link"
or exit 1

if test -e "$cli_link"; or test -L "$cli_link"
    if not test -L "$cli_link"
        echo "spacewright install: refusing to replace non-symlink $cli_link" >&2
        exit 1
    end
    set -l existing_cli_target (readlink "$cli_link")
    if not string match -q "$prefix/*" -- "$existing_cli_target"
        echo "spacewright install: refusing to replace unmanaged symlink $cli_link" >&2
        exit 1
    end
end
command ln -sfn "$current_link/bin/spacewright" "$cli_link"
or exit 1

printf 'installed SpaceWright %s\npackage=%s\nbootstrap=%s\ncli=%s\n' "$package_version" "$release_root" "$bootstrap_link" "$cli_link"

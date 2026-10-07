#!/usr/bin/env fish

argparse 'output=' 'tag=' -- $argv
or exit 2

set -l script_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $script_file))
set -l package_version (string trim < "$package_root/VERSION")

if not string match -qr '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$' -- "$package_version"
    echo "spacewright package: invalid version: $package_version" >&2
    exit 2
end

set -l expected_tag "v$package_version"
if set -q _flag_tag; and test "$_flag_tag" != "$expected_tag"
    echo "spacewright package: tag $_flag_tag does not match VERSION ($expected_tag)" >&2
    exit 2
end

set -l output_root "$package_root/dist"
set -q _flag_output; and set output_root $_flag_output
command mkdir -p "$output_root"
or exit 1
set output_root (path resolve "$output_root")

set -l staging_root (mktemp -d /private/tmp/spacewright-release.XXXXXX)
or exit 1
function cleanup_release_staging --on-event fish_exit --inherit-variable staging_root
    command rm -rf "$staging_root"
end

set -l archive_root "spacewright-$package_version"
set -l package_dir "$staging_root/$archive_root"
command mkdir -p "$package_dir"
or exit 1

for item in \
        bin \
        conf.d \
        config \
        configurator \
        docs \
        examples \
        lib \
        packaging \
        schemas \
        scripts \
        CHANGELOG.md \
        LICENSE \
        README.md \
        SECURITY.md \
        VERSION
    if not test -e "$package_root/$item"
        echo "spacewright package: source is missing $item" >&2
        exit 1
    end
    command cp -R "$package_root/$item" "$package_dir/"
    or exit 1
end

set -l archive "$output_root/$archive_root.tar.gz"
set -l checksums "$output_root/SHA256SUMS"
command rm -f "$archive" "$checksums"

# Normalize archive metadata so rerunning a tag produces byte-identical assets.
command find "$package_dir" -exec touch -h -t 198001010000 {} +
or exit 1
env COPYFILE_DISABLE=1 tar -C "$staging_root" \
    --uid 0 --gid 0 --uname root --gname wheel \
    -cf - "$archive_root" \
    | command gzip -n > "$archive"
or exit 1

set -l digest (command shasum -a 256 "$archive" | string split ' ')[1]
printf '%s  %s\n' "$digest" (path basename "$archive") > "$checksums"

printf 'archive=%s\nchecksums=%s\nsha256=%s\n' "$archive" "$checksums" "$digest"

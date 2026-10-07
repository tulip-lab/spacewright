#!/usr/bin/env fish

argparse 'version=' 'sha256=' 'url=' 'output=' -- $argv
or exit 2

for required in version sha256 url output
    set -l flag_name "_flag_$required"
    if not set -q $flag_name; or test -z "$$flag_name"
        echo "spacewright formula: --$required is required" >&2
        exit 2
    end
end

if not string match -qr '^[0-9]+\.[0-9]+\.[0-9]+([+-][0-9A-Za-z.-]+)?$' -- "$_flag_version"
    echo "spacewright formula: invalid version: $_flag_version" >&2
    exit 2
end
if not string match -qr '^[0-9a-f]{64}$' -- "$_flag_sha256"
    echo 'spacewright formula: sha256 must be 64 lowercase hexadecimal characters' >&2
    exit 2
end
if not string match -qr '^https://github\.com/tulip-lab/spacewright/releases/download/v[^/]+/spacewright-[^/]+\.tar\.gz$' -- "$_flag_url"
    echo "spacewright formula: unexpected release URL: $_flag_url" >&2
    exit 2
end

set -l script_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $script_file))
set -l template "$package_root/packaging/homebrew/spacewright.rb.in"
set -l output_dir (path dirname "$_flag_output")
command mkdir -p "$output_dir"
or exit 1

string replace -a '@VERSION@' "$_flag_version" < "$template" \
    | string replace -a '@SHA256@' "$_flag_sha256" \
    | string replace -a '@URL@' "$_flag_url" \
    > "$_flag_output"

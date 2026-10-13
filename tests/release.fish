#!/usr/bin/env fish

set -l test_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $test_file))
set -l test_root (mktemp -d /private/tmp/spacewright-release-test.XXXXXX)
or exit 1
function cleanup_release_test --on-event fish_exit --inherit-variable test_root
    command rm -rf "$test_root"
end

set -l release_version (string trim < "$package_root/VERSION")
fish --no-config "$package_root/scripts/package-release.fish" --tag "v$release_version" --output "$test_root/dist" >/dev/null
or exit 1
fish --no-config "$package_root/scripts/package-release.fish" --tag "v$release_version" --output "$test_root/dist-repeat" >/dev/null
or exit 2

set -l archive "$test_root/dist/spacewright-$release_version.tar.gz"
set -l checksums "$test_root/dist/SHA256SUMS"
test -f "$archive"
or exit 3
test -f "$checksums"
or exit 4

cd "$test_root/dist"
command shasum -a 256 -c SHA256SUMS >/dev/null
or exit 5
command cmp -s "$archive" "$test_root/dist-repeat/spacewright-$release_version.tar.gz"
or exit 6

set -l archive_entries (command tar -tzf "$archive")
contains -- "spacewright-$release_version/bin/spacewright" $archive_entries
or exit 7
contains -- "spacewright-$release_version/configurator/server.mjs" $archive_entries
or exit 8
contains -- "spacewright-$release_version/scripts/install.fish" $archive_entries
or exit 9
contains -- "spacewright-$release_version/package.json" $archive_entries
or exit 16
contains -- "spacewright-$release_version/package-lock.json" $archive_entries
or exit 17
contains -- "spacewright-$release_version/node_modules/yaml/package.json" $archive_entries
or exit 18
contains -- "spacewright-$release_version/helpers/spacewright-banner.swift" $archive_entries
or exit 19
for entry in $archive_entries
    if string match -qr '/(\.git|tests|AGENTS\.md)(/|$)' -- "$entry"
        echo "unexpected release entry: $entry" >&2
        exit 10
    end
    if string match -q '*/node_modules/*' -- "$entry"
        set -l dependency_path (string replace -r '^.*/node_modules/' '' -- "$entry")
        if test -n "$dependency_path"; and test "$dependency_path" != .package-lock.json; and not string match -qr '^(\.bin(/yaml)?/?|yaml(/.*)?)$' -- "$dependency_path"
            echo "unexpected production dependency: $entry" >&2
            exit 20
        end
    end
end

set -l extracted_root "$test_root/extracted"
command mkdir -p "$extracted_root"
command tar -xzf "$archive" -C "$extracted_root"
or exit 21
set -l extracted_package "$extracted_root/spacewright-$release_version"
set -l server_log "$test_root/release-server.log"
env HOME="$test_root/home" node "$extracted_package/configurator/server.mjs" \
    "--package-root=$extracted_package" \
    "--config-root=$test_root/config" \
    "--state-root=$test_root/state" \
    --port=0 --no-open >"$server_log" 2>&1 &
set -l server_pid $last_pid
for attempt in (seq 1 30)
    grep -q 'SPACEWRIGHT_CONFIGURATOR_URL=' "$server_log"; and break
    sleep 0.1
end
grep -q 'SPACEWRIGHT_CONFIGURATOR_URL=' "$server_log"
or begin
    command kill "$server_pid" 2>/dev/null
    cat "$server_log" >&2
    exit 22
end
command kill "$server_pid"
wait "$server_pid"

set -l digest (string split ' ' < "$checksums")[1]
set -l formula "$test_root/Formula/spacewright.rb"
set -l url "https://github.com/tulip-lab/spacewright/releases/download/v$release_version/spacewright-$release_version.tar.gz"
fish --no-config "$package_root/scripts/render-homebrew-formula.fish" \
    --version "$release_version" \
    --sha256 "$digest" \
    --url "$url" \
    --output "$formula"
or exit 11

command ruby -c "$formula" >/dev/null
or exit 12
grep -q "version \"$release_version\"" "$formula"
or exit 13
grep -q "sha256 \"$digest\"" "$formula"
or exit 14
grep -q "url \"$url\"" "$formula"
or exit 15

echo "OK      release archive, checksum, and Homebrew formula rendering"

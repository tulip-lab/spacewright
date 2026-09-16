#!/usr/bin/env fish

set -l script_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $script_file))
cd "$package_root"
or exit 1

for fish_file in (find bin conf.d lib scripts tests -type f -name '*.fish' -o -path 'bin/spacewright')
    fish -n "$fish_file"
    or exit 1
end

jq empty config/defaults.json examples/config.json schemas/spacewright.schema.json
or exit 1

fish tests/config.fish
or exit 1
fish tests/install.fish
or exit 1

env -u SPACEWRIGHT_PACKAGE_ROOT -u SPACEWRIGHT_ROOT -u SPACEWRIGHT_CONFIG_ROOT \
    fish --no-config -c 'source conf.d/spacewright.fish; set -gx WORKSPACE_TEST_SOURCE_ROOT "$SPACEWRIGHT_ROOT"; work_smoke'
or exit 1

echo "OK      SpaceWright release checks"

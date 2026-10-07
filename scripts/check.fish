#!/usr/bin/env fish

set -l script_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $script_file))
cd "$package_root"
or exit 1

for fish_file in (find bin conf.d lib scripts tests -type f -name '*.fish' -o -path 'bin/spacewright')
    fish -n "$fish_file"
    or exit 1
end

jq empty config/defaults.json examples/config.json examples/config-v2.json schemas/spacewright.schema.json schemas/spacewright-v2.schema.json
or exit 1

node --test configurator/test/*.test.mjs
or exit 1
fish tests/config-v2.fish
or exit 1
fish tests/config.fish
or exit 1
fish tests/install.fish
or exit 1
fish tests/release.fish
or exit 1

set -l smoke_config_root (mktemp -d /private/tmp/spacewright-smoke-config.XXXXXX)
env -u SPACEWRIGHT_PACKAGE_ROOT -u SPACEWRIGHT_ROOT \
    SPACEWRIGHT_CONFIG_ROOT="$smoke_config_root" \
    fish --no-config -c 'source conf.d/spacewright.fish; set -gx WORKSPACE_TEST_SOURCE_ROOT "$SPACEWRIGHT_ROOT"; work_smoke'
or exit 1

echo "OK      SpaceWright release checks"

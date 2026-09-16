if test "$SPACEWRIGHT_USE_LEGACY" = 1
    return 0
end

set -l spacewright_bootstrap_file (path resolve (status filename))
set -l spacewright_package_root (path dirname (path dirname $spacewright_bootstrap_file))

if not set -q SPACEWRIGHT_ROOT; or test -z "$SPACEWRIGHT_ROOT"
    set -gx SPACEWRIGHT_ROOT "$spacewright_package_root/lib/spacewright"
end

source "$SPACEWRIGHT_ROOT/common/spacewright_paths.fish"
source "$SPACEWRIGHT_ROOT/common/work_reload.fish"
work_reload

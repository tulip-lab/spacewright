if set -q WORKSPACE_TEST_SOURCE_ROOT; and test -n "$WORKSPACE_TEST_SOURCE_ROOT"
    set -gx SPACEWRIGHT_ROOT "$WORKSPACE_TEST_SOURCE_ROOT"
    source "$SPACEWRIGHT_ROOT/common/spacewright_paths.fish"
    source "$SPACEWRIGHT_ROOT/common/work_reload.fish"
end

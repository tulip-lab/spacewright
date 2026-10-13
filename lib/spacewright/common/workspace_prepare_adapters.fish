function workspace_prepare_adapters --description "Run only explicitly planned app preparation, before new fixed identities are selected"
    workspace_execution_owned; or return 1
    test -r "$SPACEWRIGHT_EXECUTION_ENVELOPE"; or return 1
    set -l total (jq '.plan.preparations | length' "$SPACEWRIGHT_EXECUTION_ENVELOPE")
    or return 1
    for index in (seq 0 (math "$total - 1"))
        command node "$SPACEWRIGHT_PACKAGE_ROOT/configurator/execution-cli.mjs" prepare-operation "$index"
        or return $status
    end
end

function workspace_execution_owned --description "Verify execution token and process ancestry against the shared lock"
    command node "$SPACEWRIGHT_PACKAGE_ROOT/configurator/execution-cli.mjs" verify
end

function workspace_execute_pinned --description "Apply only identities and actions carried by the active plan"
    command node "$SPACEWRIGHT_PACKAGE_ROOT/configurator/execution-cli.mjs" pinned-workspace $argv
end

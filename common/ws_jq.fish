function ws_jq --description "Run jq against JSON with a bounded timeout"
    set -l timeout_seconds "$WORKSPACE_JQ_TIMEOUT_SECONDS"

    if test -z "$timeout_seconds"
        set timeout_seconds 3
    end

    perl -e 'alarm shift; exec @ARGV' $timeout_seconds jq $argv
end

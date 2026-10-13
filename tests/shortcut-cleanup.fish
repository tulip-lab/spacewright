source lib/spacewright/common/workspace_finalize.fish
source lib/spacewright/common/workspace_cleanup_after_shortcut.fish
set -g spaces '[{"uuid":"HOME","index":1,"display":1,"label":""},{"uuid":"TARGET","index":2,"display":1,"label":"chat"},{"uuid":"EMPTY","index":3,"display":1,"label":"review"},{"uuid":"BLANK","index":4,"display":1,"label":""},{"uuid":"CUSTOM","index":5,"display":1,"label":"personal"},{"uuid":"ONLY","index":6,"display":2,"label":""},{"uuid":"EXTRA","index":7,"display":2,"label":"sandbox_tall"}]'
set -g windows '[{"id":10,"space":2,"app":"Chat","can-move":true}]'
set -g policy managed
set -g scenario $argv[1]
function workspace_execution_owned; return 0; end
function spacewright_config_effective
    printf '{"settings":{"cleanupEmptySpaces":"%s"},"workspaces":{"chat":{"label":"chat"},"review":{"label":"review"}}}' $policy
end
function ws_jq; command jq $argv; end
function resolve_workspace_primary_display; echo 1; end
function ws_query_spaces
    if test "$scenario" = renamed; and test "$argv[2]" = before-EMPTY
        set -g spaces (echo $spaces | jq -c 'map(if .uuid == "EMPTY" then .label = "personal2" else . end)')
    end
    echo $spaces
end
function ws_query_windows
    test "$scenario" != discovery_failed; or return 1
    if test "$scenario" = became_occupied; and test "$argv[2]" = before-EMPTY
        set -g windows (echo $windows | jq -c '. + [{id:11,space:3,app:"Other"}]')
    end
    echo $windows
end
function ws_query_current_space; echo '{"uuid":"HOME","index":1}'; end
function ws_focus_space; echo FOCUS=$argv[1]; end
function ws_yabai
    test "$scenario" != destruction_failed; or return 7
    test "$scenario" != ineffective; or return 0
    echo DESTROY=$argv[3]
    set -g windows (echo $windows | jq -c --argjson index $argv[3] 'map(if .space > $index then .space -= 1 else . end)')
    set -g spaces (echo $spaces | jq -c --argjson index $argv[3] 'map(select(.index != $index) | if .index > $index then .index -= 1 else . end)')
end
switch "$scenario"
    case disabled
        set -g policy none
    case occupied
        set -g windows '[{"id":10,"space":2,"app":"Chat"},{"id":11,"space":3,"app":"Other","can-move":false,"is-visible":false,"role":"AXWindow"}]'
    case sticky
        set -g windows '[{"id":10,"space":2,"app":"Chat"},{"id":11,"space":3,"is-sticky":true}]'
    case no_home
        set -g spaces (echo $spaces | jq -c 'map(select(.uuid != "HOME"))')
end
set -l flags
test "$scenario" = dry_run; and set flags --dry-run
workspace_cleanup_after_shortcut $flags
echo status=$status
echo $spaces | jq -c '[.[].uuid]'

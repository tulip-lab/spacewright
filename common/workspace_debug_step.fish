function workspace_debug_step --description "Print a workspace debug step when WORKSPACE_DEBUG_STEPS=1"
    if test "$WORKSPACE_DEBUG_STEPS" = "1"
        echo "[step] $argv" >&2
    end
end

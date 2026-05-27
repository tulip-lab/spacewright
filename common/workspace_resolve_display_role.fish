function workspace_resolve_display_role --description "Resolve a workspace display role to a yabai display index"
    set -l role $argv[1]

    switch "$role"
        case primary solo
            resolve_workspace_primary_display
        case wide tall
            resolve_workspace_external_display $role
        case '*'
            echo "[WARN] workspace_resolve_display_role: invalid display role: $role" >&2
            return 2
    end
end

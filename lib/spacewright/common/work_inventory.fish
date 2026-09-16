function work_inventory --description "Print a read-only workspace workflow inventory"
    echo "===== WORKSPACE INVENTORY ====="
    echo

    echo "===== SPACEWRIGHT CONFIG ====="
    if workspace_config_check
        set -l config (spacewright_config_effective | string collect)
        printf "version=%s\n" (printf "%s\n" "$config" | jq -r '.version')
        printf "apps=%s\n" (printf "%s\n" "$config" | jq -r '.apps | length')
        printf "workspaces=%s\n" (printf "%s\n" "$config" | jq -r '.workspaces | length')
        printf "modes=%s\n" (printf "%s\n" "$config" | jq -r '.modes | length')
        printf "user_config=%s\n" (spacewright_config_user_file)
    else
        echo "invalid"
    end
    echo

    echo "===== TOP-LEVEL ENTRIES ====="
    for row in (workspace_top_level_entry_rows)
        set -l parts (string split \t -- "$row")
        printf "%-18s %s\n" $parts[1] $parts[3]
    end
    echo

    echo "===== MODULE ENTRIES ====="
    printf "%-10s %-20s %s\n" "module" "entries" "managed apps"
    for row in (workspace_module_entry_rows)
        set -l parts (string split \t -- "$row")
        printf "%-10s %-20s %s\n" $parts[1] $parts[2] $parts[3]
    end
    echo

    echo "===== WORKSPACE COMMAND MAP ====="
    printf "%-24s %-12s %-12s %s\n" "workspace" "mode" "display role" "apps"
    for row in (workspace_command_map_rows)
        set -l parts (string split \t -- "$row")
        printf "%-24s %-12s %-12s %s\n" $parts[1] $parts[2] $parts[3] $parts[4]
    end
    echo

    echo "===== OWNERSHIP POLICY ====="
    workspace_print_ownership_policy
    echo

    echo "===== DISPLAY ENTRIES ====="
    for row in (workspace_display_entry_rows)
        set -l parts (string split \t -- "$row")
        printf "%-24s %s\n" $parts[1] $parts[2]
    end
    echo

    echo "===== COMMON HELPERS ====="
    for row in (workspace_common_helper_rows)
        set -l parts (string split \t -- "$row")
        printf "%-32s %s\n" $parts[1] $parts[2]
    end
    echo

    echo "===== DEPENDENCIES ====="
    for row in (workspace_dependency_rows)
        set -l parts (string split \t -- "$row")
        printf "%-18s %s\n" $parts[1] $parts[2]
    end
end

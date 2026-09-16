function work_command_check --description "Check that documented workspace command entry points are loaded"
    set -l commands (workspace_required_command_names)

    set -l missing_count 0

    echo "===== WORKSPACE COMMAND CHECK ====="

    for command_name in $commands
        if functions -q $command_name
            printf "OK      %s\n" "$command_name"
        else
            printf "MISSING %s\n" "$command_name"
            set missing_count (math $missing_count + 1)
        end
    end

    echo
    printf "missing_count=%s\n" "$missing_count"

    test "$missing_count" -eq 0
end

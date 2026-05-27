function workspace_run_cleanup_specs --description "Run workspace cleanup specs such as gtd:tall or legacy cleanup functions"
    for cleanup_spec in $argv
        if string match -q '*:*' -- $cleanup_spec
            set -l cleanup_parts (string split -m1 ':' -- $cleanup_spec)
            workspace_cleanup_mode_spaces $cleanup_parts[1] $cleanup_parts[2]
            or return 1
        else if functions -q $cleanup_spec
            $cleanup_spec
            or return 1
        else
            echo "[WARN] workspace_run_cleanup_specs: cleanup spec not found: $cleanup_spec" >&2
            return 1
        end
    end
end

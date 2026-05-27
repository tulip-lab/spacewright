function workspace_run_mode_steps --description "Run workspace mode steps with shared cleanup and child-cleanup suppression"
    set -l dry_run 0
    set -l clean_argv

    for arg in $argv
        if test "$arg" = "--dry-run"
            set dry_run 1
        else
            set -a clean_argv $arg
        end
    end

    set argv $clean_argv

    set -l separator_index (contains -i -- -- $argv)
    if test -z "$separator_index"
        echo "usage: workspace_run_mode_steps <cleanup-spec ...> -- <command ...>" >&2
        return 2
    end

    set -l cleanup_specs $argv[1..(math $separator_index - 1)]
    set -l commands $argv[(math $separator_index + 1)..-1]

    if test (count $commands) -eq 0
        echo "usage: workspace_run_mode_steps <cleanup-spec ...> -- <command ...>" >&2
        return 2
    end

    set -l failed 0

    if test "$dry_run" -eq 1
        printf "dry_run=workspace_run_mode_steps\n"
        printf "cleanup=%s\n" "$cleanup_specs"
        printf "commands=%s\n" "$commands"
        return 0
    end

    for cleanup_spec in $cleanup_specs
        workspace_run_step "cleanup $cleanup_spec" workspace_run_cleanup_specs $cleanup_spec
        or set failed 1
    end

    set -l old_skip_labeled_cleanup "$WORKSPACE_SKIP_LABELED_CLEANUP"
    set -gx WORKSPACE_SKIP_LABELED_CLEANUP 1

    for command_name in $commands
        workspace_run_step "$command_name" $command_name
        or set failed 1
    end

    if test -n "$old_skip_labeled_cleanup"
        set -gx WORKSPACE_SKIP_LABELED_CLEANUP "$old_skip_labeled_cleanup"
    else
        set -e WORKSPACE_SKIP_LABELED_CLEANUP
    end

    for cleanup_spec in $cleanup_specs
        workspace_run_step "final cleanup $cleanup_spec" workspace_run_cleanup_specs $cleanup_spec
        or set failed 1
    end

    return $failed
end

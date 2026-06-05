function workspace_debug_step --description "Print a workspace debug step when WORKSPACE_DEBUG_STEPS=1"
    if test "$WORKSPACE_DEBUG_STEPS" = "1"
        echo "[step] $argv" >&2
    end
end

function workspace_run_step --description "Run a workspace step with visible timing"
    if test (count $argv) -lt 2
        echo "usage: workspace_run_step <label> <command> [args...]" >&2
        return 1
    end

    set -l label $argv[1]
    set -e argv[1]

    echo "==> $label"

    set -l started_at (perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000')
    $argv
    set -l status_code $status
    set -l ended_at (perl -MTime::HiRes=time -e 'printf "%.0f\n", time * 1000')
    set -l elapsed (math $ended_at - $started_at)

    if test "$status_code" -eq 0
        echo "<== $label {$elapsed}ms" | string replace "{$elapsed}" "$elapsed"
    else
        echo "[WARN] $label failed status=$status_code elapsed={$elapsed}ms" | string replace "{$elapsed}" "$elapsed" >&2
    end

    return $status_code
end

function workspace_run_cleanup_specs --description "Run workspace cleanup specs such as gtd:tall or legacy cleanup functions"
    set -l had_cleanup_spaces_cache 0
    set -l old_cleanup_spaces_cache

    if set -q __WORKSPACE_CLEANUP_SPACES_JSON
        set had_cleanup_spaces_cache 1
        set old_cleanup_spaces_cache "$__WORKSPACE_CLEANUP_SPACES_JSON"
    end

    set -l needs_cleanup_spaces_cache 0
    for cleanup_spec in $argv
        if string match -q '*:*' -- $cleanup_spec
            set needs_cleanup_spaces_cache 1
            break
        end
    end

    if test "$needs_cleanup_spaces_cache" -eq 1
        set -l cleanup_spaces_json (workspace_cleanup_query_spaces)
        if test $status -eq 0
            set -g __WORKSPACE_CLEANUP_SPACES_JSON "$cleanup_spaces_json"
        else
            set -g __WORKSPACE_CLEANUP_SPACES_JSON ""
        end
    end

    set -l failed 0
    for cleanup_spec in $argv
        if string match -q '*:*' -- $cleanup_spec
            set -l cleanup_parts (string split -m1 ':' -- $cleanup_spec)
            workspace_cleanup_mode_spaces $cleanup_parts[1] $cleanup_parts[2]
            or begin
                set failed 1
                break
            end
        else if functions -q $cleanup_spec
            $cleanup_spec
            or begin
                set failed 1
                break
            end
        else
            echo "[WARN] workspace_run_cleanup_specs: cleanup spec not found: $cleanup_spec" >&2
            set failed 1
            break
        end
    end

    if test "$had_cleanup_spaces_cache" -eq 1
        set -g __WORKSPACE_CLEANUP_SPACES_JSON "$old_cleanup_spaces_cache"
    else
        set -e __WORKSPACE_CLEANUP_SPACES_JSON
    end

    return $failed
end

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

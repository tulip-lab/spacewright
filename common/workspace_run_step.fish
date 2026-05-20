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

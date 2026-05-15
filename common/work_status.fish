function work_status
    echo "===== WORKSPACE DIAGNOSTICS ====="
    work_diagnostics

    echo
    echo "===== WORKSPACE SNAPSHOT ====="
    workspace_status_snapshot

    set -l had_skip_status_snapshot 0
    set -l previous_skip_status_snapshot

    if set -q WORKSPACE_SKIP_STATUS_SNAPSHOT
        set had_skip_status_snapshot 1
        set previous_skip_status_snapshot $WORKSPACE_SKIP_STATUS_SNAPSHOT
    end

    set -g WORKSPACE_SKIP_STATUS_SNAPSHOT 1

    echo "===== GTD ====="
    gtd_status

    echo
    echo "===== CODING ====="
    coding_status

    echo
    echo "===== OFFICE ====="
    office_status

    echo
    echo "===== RESEARCH ====="
    research_status

    if test "$had_skip_status_snapshot" -eq 1
        set -g WORKSPACE_SKIP_STATUS_SNAPSHOT $previous_skip_status_snapshot
    else
        set -e WORKSPACE_SKIP_STATUS_SNAPSHOT
    end
end

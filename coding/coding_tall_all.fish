function coding_tall_all --description "Arrange all coding tall workspaces including internal fixed workspaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Enter the complete coding tall mode by arranging:
    #     - all coding tall-mode workspaces
    #     - internal fixed coding workspaces
    #
    # Notes:
    #   `coding_tall` already performs the required opposite-mode cleanup, so
    #   this wrapper does not repeat cleanup again.
    # -------------------------------------------------------------------------

    set -l failed 0

    workspace_run_step "coding tall mode" coding_tall
    or set failed 1

    workspace_run_step "coding control internal" coding_control
    or set failed 1

    return $failed
end

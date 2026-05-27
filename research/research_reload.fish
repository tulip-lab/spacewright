function research_reload --description "Reload all research workspace functions and helpers"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full research workspace function set after editing files.
    #
    # Reload order:
    #   1. Common workspace helpers
    #   2. Research cleanup helpers
    #   3. Concrete research workspace functions
    #   4. Status / inspection helpers
    # -------------------------------------------------------------------------

    # 1. Common workspace helpers
    if test "$WORKSPACE_SKIP_COMMON_RELOAD" != "1"
        source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
        source_workspace_common
    end

    # 2. Concrete research workspace functions
    source ~/.config/fish/functions/workspace/research/solo/research_solo.fish
    source ~/.config/fish/functions/workspace/research/wide/research_wide.fish
    source ~/.config/fish/functions/workspace/research/tall/research_tall.fish

    # 3. Status / inspection helpers
    source ~/.config/fish/functions/workspace/research/research_status.fish
end

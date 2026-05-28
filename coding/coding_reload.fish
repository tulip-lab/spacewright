function coding_reload --description "Reload all coding workspace functions and helpers"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full coding workspace function set after editing files.
    #
    # Reload order:
    #   1. Common workspace helpers
    #   2. Coding entry and internal workspace functions
    # -------------------------------------------------------------------------

    # 1. Common workspace helpers
    if test "$WORKSPACE_SKIP_COMMON_RELOAD" != "1"
        source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
        source_workspace_common
    end

    # 2. Coding entry and internal workspace functions
    source ~/.config/fish/functions/workspace/coding/coding_entries.fish
    source ~/.config/fish/functions/workspace/coding/internal/coding_control.fish

end

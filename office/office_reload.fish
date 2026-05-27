function office_reload --description "Reload all office workspace functions and helpers"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full office workspace function set after editing files.
    #
    # Reload order:
    #   1. Common workspace helpers
    #   2. Office entry functions
    #   3. Status / inspection helpers
    # -------------------------------------------------------------------------

    # 1. Common workspace helpers
    if test "$WORKSPACE_SKIP_COMMON_RELOAD" != "1"
        source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
        source_workspace_common
    end

    # 2. Office entry functions
    source ~/.config/fish/functions/workspace/office/office_entries.fish

    # 3. Status / inspection helpers
    source ~/.config/fish/functions/workspace/office/office_status.fish
end

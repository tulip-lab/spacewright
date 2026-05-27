function coding_reload --description "Reload all coding workspace functions and helpers"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full coding workspace function set after editing files.
    #
    # Reload order:
    #   1. Common workspace helpers
    #   2. Coding cleanup helpers
    #   3. Concrete coding workspace functions
    #   4. Aggregate entry functions
    #   5. Status / inspection helpers
    # -------------------------------------------------------------------------

    # 1. Common workspace helpers
    if test "$WORKSPACE_SKIP_COMMON_RELOAD" != "1"
        source ~/.config/fish/functions/workspace/common/source_workspace_common.fish
        source_workspace_common
    end

    # 2. Concrete coding workspace functions
    source ~/.config/fish/functions/workspace/coding/solo/coding_editor_solo.fish
    source ~/.config/fish/functions/workspace/coding/solo/coding_solo.fish
    source ~/.config/fish/functions/workspace/coding/wide/coding_editor_wide.fish
    source ~/.config/fish/functions/workspace/coding/wide/coding_wide.fish
    source ~/.config/fish/functions/workspace/coding/tall/coding_editor_tall.fish
    source ~/.config/fish/functions/workspace/coding/tall/coding_tall.fish
    source ~/.config/fish/functions/workspace/coding/internal/coding_control.fish

    # 3. Aggregate entry functions
    source ~/.config/fish/functions/workspace/coding/coding_wide_all.fish
    source ~/.config/fish/functions/workspace/coding/coding_tall_all.fish

    # 4. Status / inspection helpers
    source ~/.config/fish/functions/workspace/coding/coding_status.fish
    source ~/.config/fish/functions/workspace/coding/coding_mode_status.fish
end

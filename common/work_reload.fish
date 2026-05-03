function work_reload --description "Reload the full workspace system"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Reload the full workspace system by reloading each workspace module and
    #   the shared top-level work helpers.
    #
    # Notes:
    #   Module-specific reload functions are responsible for sourcing their own
    #   common helper dependencies.
    # -------------------------------------------------------------------------

    source ~/.config/fish/functions/workspace/display/display_reload.fish
    source ~/.config/fish/functions/workspace/gtd/gtd_reload.fish
    source ~/.config/fish/functions/workspace/coding/coding_reload.fish
    source ~/.config/fish/functions/workspace/office/office_reload.fish
    source ~/.config/fish/functions/workspace/research/research_reload.fish

    source ~/.config/fish/functions/workspace/common/work_status.fish
    source ~/.config/fish/functions/workspace/common/work_mode_status.fish
    source ~/.config/fish/functions/workspace/common/work_wide.fish
    source ~/.config/fish/functions/workspace/common/work_tall.fish
    source ~/.config/fish/functions/workspace/common/work_check.fish

    display_reload
    gtd_reload
    coding_reload
    office_reload
    research_reload
end
function __research_solo_body --description "Collect Zotero and Claude onto the solo research workspace"
    workspace_apply_primary_helper_space \
        --label research_solo \
        --display primary \
        --primary-app-key zotero \
        --helper-app-key claude \
        --helper-visible \
        --primary-grid 1:3:0:0:2:1 \
        --helper-grid 1:3:2:0:1:1 \
        research:wide research:tall $argv
end

function __research_wide_body --description "Collect Zotero and Claude onto the wide research workspace and apply the standard research layout"
    workspace_apply_primary_helper_space \
        --label research_wide \
        --display wide \
        --primary-app-key zotero \
        --helper-app-key claude \
        --primary-grid 1:3:0:0:2:1 \
        --helper-grid 1:3:2:0:1:1 \
        research:tall research:solo $argv
end

function __research_tall_body --description "Collect Zotero and Claude onto the tall research workspace and apply the standard research layout"
    workspace_apply_primary_helper_space \
        --label research_tall \
        --display tall \
        --primary-app-key zotero \
        --helper-app-key claude \
        --primary-grid 2:1:0:0:1:1 \
        --helper-grid 2:1:0:1:1:1 \
        research:wide research:solo $argv
end

function research_solo --description "Collect Zotero and Claude onto the solo research workspace"
    workspace_run_finalized_entry --mode solo --command __research_solo_body -- $argv
end

function research_wide --description "Collect Zotero and Claude onto the wide research workspace and apply the standard research layout"
    workspace_run_finalized_entry --mode wide --command __research_wide_body -- $argv
end

function research_tall --description "Collect Zotero and Claude onto the tall research workspace and apply the standard research layout"
    workspace_run_finalized_entry --mode tall --command __research_tall_body -- $argv
end

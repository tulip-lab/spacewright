function office_writing_wide --description "Collect Word and ChatGPT onto the wide office writing workspace and apply the standard writing layout"
    workspace_apply_primary_helper_space \
        --label office_writing_wide \
        --display wide \
        --primary-app-key word \
        --helper-app-key chatgpt \
        --helper-grid 1:3:0:0:1:1 \
        --primary-grid 1:3:1:0:2:1 \
        office:tall $argv
end

function office_slides_wide --description "Collect PowerPoint and ChatGPT onto the wide office slides workspace and apply the standard slides layout"
    workspace_apply_primary_helper_space \
        --label office_slides_wide \
        --display wide \
        --primary-app-key powerpoint \
        --helper-app-key chatgpt \
        --helper-grid 1:3:0:0:1:1 \
        --primary-grid 1:3:1:0:2:1 \
        office:tall $argv
end

function office_wide --description "Arrange all office wide workspaces and clean opposite-mode spaces"
    workspace_run_mode_steps office:tall -- office_writing_wide office_slides_wide $argv
end

function office_writing_tall --description "Collect Word and ChatGPT onto the tall office writing workspace and apply the standard writing layout"
    workspace_apply_primary_helper_space \
        --label office_writing_tall \
        --display tall \
        --primary-app-key word \
        --helper-app-key chatgpt \
        --helper-grid 2:1:0:0:1:1 \
        --primary-grid 2:1:0:1:1:1 \
        office:wide $argv
end

function office_slides_tall --description "Collect PowerPoint and ChatGPT onto the tall office slides workspace and apply the standard slides layout"
    workspace_apply_primary_helper_space \
        --label office_slides_tall \
        --display tall \
        --primary-app-key powerpoint \
        --helper-app-key chatgpt \
        --helper-grid 2:1:0:0:1:1 \
        --primary-grid 2:1:0:1:1:1 \
        office:wide $argv
end

function office_tall --description "Arrange all office tall workspaces and clean opposite-mode spaces"
    workspace_run_mode_steps office:wide -- office_writing_tall office_slides_tall $argv
end

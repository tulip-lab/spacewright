function coding_editor_solo --description "Collect VS Code and Codex onto the solo coding editor workspace"
    workspace_apply_primary_helper_space \
        --label coding_editor_solo \
        --display primary \
        --primary-app-key code \
        --helper-app-key codex \
        --helper-space-fallback \
        --helper-grid 1:3:0:0:1:1 \
        --primary-grid 1:3:1:0:2:1 \
        --primary-alone-grid 1:1:0:0:1:1 \
        coding:wide coding:tall $argv
end

function coding_editor_wide --description "Collect VS Code and Codex onto the wide coding editor workspace and apply the standard editor layout"
    workspace_apply_primary_helper_space \
        --label coding_editor_wide \
        --display wide \
        --primary-app-key code \
        --helper-app-key codex \
        --helper-space-fallback \
        --helper-grid 1:3:0:0:1:1 \
        --primary-grid 1:3:1:0:2:1 \
        --primary-alone-grid 1:1:0:0:1:1 \
        coding:tall coding:solo $argv
end

function coding_editor_tall --description "Collect VS Code and Codex onto the tall coding editor workspace and apply the standard editor layout"
    workspace_apply_primary_helper_space \
        --label coding_editor_tall \
        --display tall \
        --primary-app-key code \
        --helper-app-key codex \
        --helper-space-fallback \
        --helper-grid 2:1:0:0:1:1 \
        --primary-grid 2:1:0:1:1:1 \
        --primary-alone-grid 1:1:0:0:1:1 \
        coding:wide coding:solo $argv
end

function coding_solo --description "Arrange coding solo workspaces and internal coding controls"
    workspace_run_mode_steps coding:wide coding:tall -- coding_editor_solo coding_control $argv
end

function coding_wide --description "Arrange all coding wide workspaces and clean opposite-mode spaces"
    workspace_run_mode_steps coding:tall coding:solo -- coding_editor_wide $argv
end

function coding_tall --description "Arrange all coding tall workspaces and clean opposite-mode spaces"
    workspace_run_mode_steps coding:wide coding:solo -- coding_editor_tall $argv
end

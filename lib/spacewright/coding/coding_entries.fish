function __coding_editor_solo_body --description "Collect VS Code onto the solo coding editor workspace"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured coding_editor_solo $argv
        return $status
    end
    workspace_apply_primary_helper_space \
        --label coding_editor_solo \
        --display primary \
        --primary-app-key code \
        --primary-grid 1:1:0:0:1:1 \
        coding:wide coding:tall $argv
end

function __coding_editor_wide_legacy_body --description "Collect VS Code and optional ChatGPT using the legacy wide coding definition"
    workspace_apply_primary_helper_space \
        --label coding_editor_wide \
        --display wide \
        --primary-app-key code \
        --primary-grid 1:3:1:0:2:1 \
        --primary-alone-grid 1:1:0:0:1:1 \
        --helper-app-key chatgpt \
        --helper-grid 1:3:0:0:1:1 \
        coding:tall coding:solo $argv
end

function __coding_editor_wide_body --description "Collect VS Code and optional ChatGPT onto the configured wide coding workspace"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" = 1
        __coding_editor_wide_legacy_body $argv
    else
        workspace_run_configured coding_editor_wide $argv
    end
end

function __coding_editor_tall_body --description "Collect VS Code and optional ChatGPT onto the tall coding editor workspace"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured coding_editor_tall $argv
        return $status
    end
    workspace_apply_primary_helper_space \
        --label coding_editor_tall \
        --display tall \
        --primary-app-key code \
        --primary-grid 2:1:0:1:1:1 \
        --primary-alone-grid 1:1:0:0:1:1 \
        --helper-app-key chatgpt \
        --helper-grid 2:1:0:0:1:1 \
        coding:wide coding:solo $argv
end

function __coding_solo_body --description "Arrange coding solo workspaces and internal coding controls"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured coding_editor_solo $argv
        return $status
    end
    workspace_run_mode_steps coding:wide coding:tall -- coding_editor_solo coding_control $argv
end

function __coding_wide_body --description "Arrange all coding wide workspaces and clean opposite-mode spaces"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured coding_editor_wide $argv
        return $status
    end
    workspace_run_mode_steps coding:tall coding:solo -- coding_editor_wide $argv
end

function __coding_tall_body --description "Arrange all coding tall workspaces and clean opposite-mode spaces"
    if test "$SPACEWRIGHT_CONFIG_DISABLE" != 1
        workspace_run_configured coding_editor_tall $argv
        return $status
    end
    workspace_run_mode_steps coding:wide coding:solo -- coding_editor_tall $argv
end

function coding_editor_wide --description "Collect VS Code and optional ChatGPT onto the wide coding editor workspace"
    workspace_run_public_workspace_entry --workspace coding_editor --mode wide --command __coding_editor_wide_body -- $argv
end

function coding_editor_tall --description "Collect VS Code and optional ChatGPT onto the tall coding editor workspace"
    workspace_run_public_workspace_entry --workspace coding_editor --mode tall --command __coding_editor_tall_body -- $argv
end

function coding_editor_solo --description "Collect VS Code onto the solo coding editor workspace"
    workspace_run_public_workspace_entry --workspace coding_editor --mode solo --command __coding_editor_solo_body -- $argv
end

function coding_solo --description "Arrange coding solo workspaces and internal coding controls"
    workspace_run_public_workspace_entry --workspace coding_editor --mode solo --command __coding_solo_body -- $argv
end

function coding_wide --description "Arrange all coding wide workspaces and clean opposite-mode spaces"
    workspace_run_public_workspace_entry --workspace coding_editor --mode wide --command __coding_wide_body -- $argv
end

function coding_tall --description "Arrange all coding tall workspaces and clean opposite-mode spaces"
    workspace_run_public_workspace_entry --workspace coding_editor --mode tall --command __coding_tall_body -- $argv
end

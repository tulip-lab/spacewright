function gtd_support_solo --description "Collect Dia onto the solo GTD support workspace"
    gtd_apply_support_space \
        --label gtd_support_solo \
        --display primary \
        --dia-layout solo \
        gtd:wide gtd:tall $argv
end

function gtd_support_wide --description "Collect Dia onto the wide GTD support workspace and apply the standard support layout"
    gtd_apply_support_space \
        --label gtd_support_wide \
        --display wide \
        --dia-layout wide \
        gtd:tall gtd:solo $argv
end

function gtd_support_tall --description "Collect Dia onto the tall GTD support workspace and apply the standard support layout"
    gtd_apply_support_space \
        --label gtd_support_tall \
        --display tall \
        --dia-layout tall \
        gtd:wide gtd:solo $argv
end

function gtd_review_solo --description "Collect review-related windows onto the solo GTD review workspace"
    gtd_apply_review_space \
        --label gtd_review_solo \
        --display primary \
        --finder-grid 2:3:0:0:1:1 \
        --preview-grid 2:3:1:0:2:1 \
        --chatgpt-grid 2:2:0:1:1:1 \
        --notes-grid 2:2:1:1:1:1 \
        gtd:wide gtd:tall $argv
end

function gtd_review_wide --description "Collect review-related windows onto the wide GTD review workspace and apply the standard review layout"
    gtd_apply_review_space \
        --label gtd_review_wide \
        --display wide \
        --finder-grid 2:8:0:0:2:2 \
        --preview-grid 2:8:2:0:3:2 \
        --chatgpt-grid 2:8:5:0:3:1 \
        --notes-grid 2:8:5:1:3:1 \
        gtd:tall gtd:solo $argv
end

function gtd_review_tall --description "Collect review-related windows onto the tall GTD review workspace and apply the standard review layout"
    gtd_apply_review_space \
        --label gtd_review_tall \
        --display tall \
        --finder-grid 2:3:0:0:1:1 \
        --preview-grid 2:3:1:0:2:1 \
        --chatgpt-grid 2:2:0:1:1:1 \
        --notes-grid 2:2:1:1:1:1 \
        gtd:wide gtd:solo $argv
end

function gtd_mail_solo --description "Collect Thunderbird onto the solo GTD mail workspace"
    workspace_apply_primary_helper_space \
        --label gtd_mail_solo \
        --display primary \
        --primary-app-key thunderbird \
        --primary-space-fallback \
        --primary-grid 1:1:0:0:1:1 \
        gtd:wide gtd:tall $argv
end

function gtd_mail_wide --description "Collect Thunderbird onto the wide GTD mail workspace and apply the standard mail layout"
    workspace_apply_primary_helper_space \
        --label gtd_mail_wide \
        --display wide \
        --primary-app-key thunderbird \
        --primary-space-fallback \
        --primary-grid 1:5:2:0:3:1 \
        gtd:tall gtd:solo $argv
end

function gtd_mail_tall --description "Collect Thunderbird onto the tall GTD mail workspace and apply the standard tall mail layout"
    workspace_apply_primary_helper_space \
        --label gtd_mail_tall \
        --display tall \
        --primary-app-key thunderbird \
        --primary-space-fallback \
        --primary-grid 2:1:0:1:1:1 \
        gtd:wide gtd:solo $argv
end

function gtd_meeting_solo --description "Collect meeting apps onto the solo GTD meeting workspace"
    gtd_apply_meeting_space \
        --label gtd_meeting_solo \
        --display primary \
        --zoom-grid 2:3:0:0:1:1 \
        --teams-grid 2:3:0:1:1:1 \
        --outlook-grid 2:3:1:0:2:2 \
        gtd:wide gtd:tall $argv
end

function gtd_meeting_wide --description "Collect Outlook, Zoom and Teams onto the wide GTD meeting workspace and apply the standard meeting layout"
    gtd_apply_meeting_space \
        --label gtd_meeting_wide \
        --display wide \
        --zoom-grid 2:5:0:0:2:1 \
        --teams-grid 2:5:0:1:2:1 \
        --outlook-grid 2:5:2:0:3:2 \
        gtd:tall gtd:solo $argv
end

function gtd_meeting_tall --description "Collect Outlook, Zoom and Teams onto the tall GTD meeting workspace and apply the standard meeting layout"
    gtd_apply_meeting_space \
        --label gtd_meeting_tall \
        --display tall \
        --zoom-grid 2:2:0:0:1:1 \
        --teams-grid 2:2:1:0:1:1 \
        --outlook-grid 2:1:0:1:1:1 \
        gtd:wide gtd:solo $argv
end

function gtd_solo_all --description "Arrange GTD solo workspaces including internal fixed workspaces"
    workspace_run_mode_steps gtd:wide gtd:tall -- gtd_support_solo gtd_mail_solo gtd_meeting_solo gtd_review_solo gtd_chat gtd_calendar $argv
end

function gtd_wide --description "Arrange all GTD wide workspaces and clean opposite-mode spaces"
    workspace_run_mode_steps gtd:tall gtd:solo -- gtd_support_wide gtd_review_wide gtd_mail_wide gtd_meeting_wide $argv
end

function gtd_tall --description "Arrange all GTD tall workspaces and clean opposite-mode spaces"
    workspace_run_mode_steps gtd:wide gtd:solo -- gtd_support_tall gtd_review_tall gtd_mail_tall gtd_meeting_tall $argv
end

function workspace_execution_owned --description "Verify execution token and process ancestry against the shared lock"
    command node "$SPACEWRIGHT_PACKAGE_ROOT/configurator/execution-cli.mjs" verify
end

function workspace_execute_pinned --description "Apply only identities and actions carried by the active plan"
    set -l runtime_id $argv[1]
    workspace_execution_owned; or return 1
    set -l envelope "$SPACEWRIGHT_EXECUTION_ENVELOPE"
    test -r "$envelope"; or return 1
    set -l workspace (jq -c --arg id "$runtime_id" '.plan.workspaces[] | select(.runtimeId == $id)' "$envelope")
    test -n "$workspace"; or return 1
    set -l id (printf '%s\n' "$workspace" | jq -r '.workspaceId')
    set -l label (printf '%s\n' "$workspace" | jq -r '.label')
    set -l space_uuid (printf '%s\n' "$workspace" | jq -r '.targetSpace.uuid // empty')
    set -l spaces (ws_query_spaces workspace_execute_pinned preflight); or return 1
    set -l target
    set -l created 0
    if test -n "$space_uuid"
        set target (printf '%s\n' "$spaces" | jq -r --arg uuid "$space_uuid" 'first(.[] | select(.uuid == $uuid) | .index) // empty')
        if test -z "$target"
            echo '[WARN] planned Space disappeared; replan required' >&2
            return 1
        end
    else
        set created 1
        set -l display (__workspace_pinned_display_index "$workspace"); or return 1
        printf '[MUTATION] {"type":"ensure_space","workspaceId":"%s","reversible":false}\n' "$id"
        set target (workspace_prepare_labeled_space "$label" "$display" float); or return 1
        set spaces (ws_query_spaces workspace_execute_pinned created); or return 1
        set space_uuid (printf '%s\n' "$spaces" | jq -r --arg label "$label" 'if ([.[] | select(.label == $label)] | length) == 1 then first(.[] | select(.label == $label) | .uuid) else empty end')
        test -n "$space_uuid"; or return 1
    end
    # A planned existing Space is never replaced by a newly selected Space.
    set -l actions (jq -c --arg id "$id" '.plan.actions[] | select(.workspaceId == $id)' "$envelope")
    for action in $actions
        set -l kind (printf '%s\n' "$action" | jq -r '.type')
        switch "$kind"
            case recover_space_label
                printf '[MUTATION] {"type":"label","spaceUuid":"%s"}\n' "$space_uuid"
                ws_yabai -m space "$target" --label "$label"; or return 1
            case move_space
                set -l display (__workspace_pinned_display_index "$workspace"); or return 1
                printf '[MUTATION] {"type":"move_space","spaceUuid":"%s"}\n' "$space_uuid"
                ws_yabai -m space "$target" --display "$display"; or return 1
            case move_window resize_window
                set target (__workspace_pinned_space_index "$space_uuid" "$workspace"); or return 1
                set -l wid (printf '%s\n' "$action" | jq -r '.windowId')
                set -l current (ws_yabai -m query --windows --window "$wid"); or return 1
                printf '%s\n' "$current" | command node "$SPACEWRIGHT_PACKAGE_ROOT/configurator/execution-cli.mjs" window-check "$wid"
                or return 1
                if test "$kind" = move_window
                    ws_window "$wid" --space "$target"; or return 1
                else
                    set -l grid (printf '%s\n' "$action" | jq -r '.grid')
                    ws_window "$wid" --grid "$grid"; or return 1
                end
        end
    end
    # Creation still moves every selected object; missing Space drifts have no move actions yet.
    if test "$created" -eq 1
        for wid in (jq -r --arg id "$id" '.plan.selectedWindows[] | select(.workspaceId == $id) | .id' "$envelope")
            set target (__workspace_pinned_space_index "$space_uuid" "$workspace"); or return 1
            set -l current (ws_yabai -m query --windows --window "$wid"); or return 1
            printf '%s\n' "$current" | command node "$SPACEWRIGHT_PACKAGE_ROOT/configurator/execution-cli.mjs" window-check "$wid"; or return 1
            ws_window "$wid" --space "$target"; or return 1
        end
    end
end

function __workspace_pinned_space_index --description "Resolve the current index without replacing the planned Space identity"
    set -l spaces (ws_query_spaces workspace_execute_pinned before-window); or return 1
    printf '%s\n' "$spaces" | jq -er --arg uuid "$argv[1]" --argjson workspace "$argv[2]" '
        first(.[] | select(.uuid == $uuid)
            | select(.label == $workspace.label or .label == $workspace.targetSpace.label) | .index) // error("planned Space identity/label changed")'
end

function __workspace_pinned_display_index --description "Resolve the planned physical display without rereading machine bindings"
    set -l displays (ws_query_displays workspace_execute_pinned target-display); or return 1
    printf '%s\n' "$displays" | jq -er --argjson workspace "$argv[1]" '
        first(.[] | select(.uuid == $workspace.targetDisplay.uuid and .frame == $workspace.targetDisplay.frame) | .index) // error("planned display changed")'
end

function coding_control --description "Collect Warp, SmartGit, and FlClash onto the internal coding control workspace and apply the standard control layout"
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=coding_control\n"
        printf "label=%s\n" coding_control
        printf "display=%s\n" primary
        printf "apps=%s,%s,%s|%s\n" (workspace_app_name warp) (workspace_app_name smartgit) (workspace_app_name flclash) (workspace_app_name thaw)
        return 0
    end

    # -------------------------------------------------------------------------
    # Workspace:
    #   coding_control
    #
    # Purpose:
    #   Move control and coordination applications to the internal coding
    #   control workspace and place them into a stable control layout.
    #
    # Target display:
    #   Workspace primary display only.
    #
    # Managed apps:
    #   - Warp
    #   - SmartGit
    #   - FlClash
    #
    # Window selection rules:
    #   - Warp:
    #       Optional. Use the first non-minimized Warp window if available.
    #   - SmartGit:
    #       Optional. Use the first non-minimized SmartGit window if available.
    #   - FlClash:
    #       Optional. If running but hidden, activate it before capture.
    #       Use visible non-minimized FlClash/Thaw windows if available.
    #
    # Creation rule:
    #   The workspace is only created if at least one of the following exists:
    #     - Warp
    #     - SmartGit
    #     - FlClash
    #
    # Layout:
    #   - Warp     -> upper 2/3 of the screen
    #   - SmartGit -> fixed absolute position and size
    #   - FlClash  -> lower 1/3 of the screen
    #
    # Notes:
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It moves only the initially captured window IDs.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    set -l label coding_control
    set -l warp_app (workspace_app_name warp)
    set -l smartgit_app (workspace_app_name smartgit)
    set -l flclash_app (workspace_app_name flclash)
    set -l flclash_apps_json (workspace_app_names_json flclash thaw)

    # -------------------------------------------------------------------------
    # 1. Find candidate windows first
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows "coding_control" initial); or return 1

    set -l flclash_running (echo $windows_json | ws_jq -r --argjson apps "$flclash_apps_json" '
        .[]
        | select(.app as $app | $apps | index($app))
        | select(.["is-minimized"]==false)
        | .id
    ')

    set -l flclash_visible (echo $windows_json | ws_jq -r --argjson apps "$flclash_apps_json" '
        first(
            .[]
            | select(.app as $app | $apps | index($app))
            | select(.["is-minimized"]==false)
            | select(.["is-visible"]==true)
            | .id
        ) // empty
    ')

    if test -n "$flclash_running" -a -z "$flclash_visible"
        perl -e 'alarm shift; exec @ARGV' 2 open -a "$flclash_app" >/dev/null 2>&1
        sleep 0.5
        set windows_json (ws_query_windows "coding_control" refresh); or return 1
    end

    set -l warp (echo $windows_json | ws_jq -r --arg app "$warp_app" '
        first(
            .[]
            | select(.app==$app)
            | select(.["is-minimized"]==false)
            | .id
        ) // empty
    ')

    set -l smartgit (echo $windows_json | ws_jq -r --arg app "$smartgit_app" '
        first(
            .[]
            | select(.app==$app)
            | select(.["is-minimized"]==false)
            | .id
        ) // empty
    ')

    set -l flclash (echo $windows_json | ws_jq -r --argjson apps "$flclash_apps_json" '
        .[]
        | select(.app as $app | $apps | index($app))
        | select(.["is-minimized"]==false)
        | select(.["is-visible"]==true)
        | .id
    ')

    # Do not create the workspace if neither helper window exists
    if test -z "$warp" -a -z "$smartgit" -a -z "$flclash"
        destroy_empty_labeled_space $label

        return 0
    end

    # -------------------------------------------------------------------------
    # 2. Resolve target display
    #    coding_control is always anchored to the workspace primary display.
    # -------------------------------------------------------------------------
    set -l target_display (resolve_workspace_primary_display)

    # -------------------------------------------------------------------------
    # 3. Prepare target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (workspace_prepare_labeled_space $label $target_display float)
    or return 1

    # -------------------------------------------------------------------------
    # 5. First-pass move
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $warp $smartgit $flclash

    # -------------------------------------------------------------------------
    # 6. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows "coding_control" final); or return 1

    set warp (echo $windows_json_final | ws_jq -r --arg app "$warp_app" --argjson s $target_space '
        first(
            .[]
            | select(.app==$app)
            | select(.space==$s)
            | select(.["is-minimized"]==false)
            | .id
        ) // empty
    ')

    set smartgit (echo $windows_json_final | ws_jq -r --arg app "$smartgit_app" --argjson s $target_space '
        first(
            .[]
            | select(.app==$app)
            | select(.space==$s)
            | select(.["is-minimized"]==false)
            | .id
        ) // empty
    ')

    set flclash (echo $windows_json_final | ws_jq -r --argjson apps "$flclash_apps_json" --argjson s $target_space '
        .[]
        | select(.app as $app | $apps | index($app))
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | select(.["is-visible"]==true)
        | .id
    ')

    # -------------------------------------------------------------------------
    # 8. Apply final layout
    #    Warp occupies the upper 2/3 region.
    #    SmartGit uses a fixed absolute position and size.
    #    FlClash uses a similar size, slightly offset from SmartGit.
    # -------------------------------------------------------------------------
    if test -n "$warp"
        ws_window $warp --grid 3:1:0:0:1:2
    end

    if test -n "$smartgit"
        ws_window $smartgit --move abs:300:60
        ws_window $smartgit --resize abs:1200:1040
    end

    for wid in $flclash
        if test -n "$wid"
            ws_window $wid --move abs:360:120
            ws_window $wid --resize abs:1200:1040
        end
    end

    # -------------------------------------------------------------------------
    # 9. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

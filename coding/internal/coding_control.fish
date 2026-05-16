function coding_control --description "Collect Warp, SmartGit, and FlClash onto the internal coding control workspace and apply the standard control layout"
    # -------------------------------------------------------------------------
    # Workspace:
    #   coding_control
    #
    # Purpose:
    #   Move control and coordination applications to the internal coding
    #   control workspace and place them into a stable control layout.
    #
    # Target display:
    #   Internal display only.
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

    # -------------------------------------------------------------------------
    # 1. Find candidate windows first
    # -------------------------------------------------------------------------
    set -l windows_json (ws_query_windows "coding_control" initial); or return 1

    set -l flclash_running (echo $windows_json | jq -r '
        .[]
        | select(.app=="FlClash" or .app=="Thaw")
        | select(.["is-minimized"]==false)
        | .id
    ')

    set -l flclash_visible (echo $windows_json | jq -r '
        .[]
        | select(.app=="FlClash" or .app=="Thaw")
        | select(.["is-minimized"]==false)
        | select(.["is-visible"]==true)
        | .id
    ' | head -n 1)

    if test -n "$flclash_running" -a -z "$flclash_visible"
        open -a FlClash
        sleep 0.5
        set windows_json (ws_query_windows "coding_control" refresh); or return 1
    end

    set -l warp (echo $windows_json | jq -r '
        .[]
        | select(.app=="Warp")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l smartgit (echo $windows_json | jq -r '
        .[]
        | select(.app=="SmartGit")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l flclash (echo $windows_json | jq -r '
        .[]
        | select(.app=="FlClash" or .app=="Thaw")
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
    #    coding_control is always anchored to the internal display.
    # -------------------------------------------------------------------------
    set -l target_display (resolve_internal_display)

    # -------------------------------------------------------------------------
    # 3. Find or create target labeled space
    # -------------------------------------------------------------------------
    set -l target_space (find_or_create_labeled_space $label $target_display)

    if test -z "$target_space"
        return 1
    end

    # -------------------------------------------------------------------------
    # 4. Normalize target space state
    # -------------------------------------------------------------------------
    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 5. First-pass move
    # -------------------------------------------------------------------------
    ws_move_windows_to_space $target_space $warp $smartgit $flclash

    # -------------------------------------------------------------------------
    # 6. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows "coding_control" final); or return 1

    set warp (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Warp")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set smartgit (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="SmartGit")
        | select(.space==$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set flclash (echo $windows_json_final | jq -r --argjson s $target_space '
        .[]
        | select(.app=="FlClash" or .app=="Thaw")
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

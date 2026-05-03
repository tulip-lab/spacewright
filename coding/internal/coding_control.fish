function coding_control --description "Collect Warp and SmartGit onto the internal coding control workspace and apply the standard control layout"
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
    #
    # Window selection rules:
    #   - Warp:
    #       Optional. Use the first non-minimized Warp window if available.
    #   - SmartGit:
    #       Optional. Use the first non-minimized SmartGit window if available.
    #
    # Creation rule:
    #   The workspace is only created if at least one of the following exists:
    #     - Warp
    #     - SmartGit
    #
    # Layout:
    #   - Warp     -> upper 2/3 of the screen
    #   - SmartGit -> fixed absolute position and size
    #
    # Notes:
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It performs a retry pass for window moves.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    set -l label coding_control
    set -l internal_uuid (get_internal_display_uuid 2>/dev/null)

    # -------------------------------------------------------------------------
    # 1. Find candidate windows first
    # -------------------------------------------------------------------------
    set -l windows_json (yabai -m query --windows)

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

    # Do not create the workspace if neither helper window exists
    if test -z "$warp" -a -z "$smartgit"
        return 0
    end

    # -------------------------------------------------------------------------
    # 2. Resolve target display
    #    coding_control is always anchored to the internal display.
    # -------------------------------------------------------------------------
    set -l target_display (resolve_target_display $internal_uuid 1)

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
    if test -n "$warp"
        yabai -m window $warp --space $target_space
    end

    if test -n "$smartgit"
        yabai -m window $smartgit --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 6. Retry pass for windows that did not move successfully
    # -------------------------------------------------------------------------
    set -l windows_json_retry (yabai -m query --windows)

    set -l warp_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="Warp")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set -l smartgit_retry (echo $windows_json_retry | jq -r --argjson s $target_space '
        .[]
        | select(.app=="SmartGit")
        | select(.space!=$s)
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -n "$warp_retry"
        yabai -m window $warp_retry --space $target_space
    end

    if test -n "$smartgit_retry"
        yabai -m window $smartgit_retry --space $target_space
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # -------------------------------------------------------------------------
    # 7. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (yabai -m query --windows)

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

    # -------------------------------------------------------------------------
    # 8. Apply final layout
    #    Warp occupies the upper 2/3 region.
    #    SmartGit uses a fixed absolute position and size.
    # -------------------------------------------------------------------------
    if test -n "$warp"
        yabai -m window $warp --grid 3:1:0:0:1:2
    end

    if test -n "$smartgit"
        yabai -m window $smartgit --move abs:300:60
        yabai -m window $smartgit --resize abs:1200:1040
    end

    # -------------------------------------------------------------------------
    # 9. Final focus and cleanup
    # -------------------------------------------------------------------------
    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_display
end
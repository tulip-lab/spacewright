function coding_control --description "Collect Warp, SmartGit, KeePassXC, and FlClash onto the internal coding control workspace and apply the standard control layout"
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        printf "dry_run=coding_control\n"
        printf "label=%s\n" coding_control
        printf "display=%s\n" primary
        printf "apps=%s,%s,%s,%s|%s\n" (workspace_app_name warp) (workspace_app_name smartgit) (workspace_app_name keepassx) (workspace_app_name flclash) (workspace_app_name thaw)
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
    #   - KeePassXC
    #   - FlClash
    #
    # Window selection rules:
    #   - Warp:
    #       Optional. Use the first non-minimized Warp window if available.
    #   - SmartGit:
    #       Optional. Use the first non-minimized SmartGit window if available.
    #   - KeePassXC:
    #       Optional. Use the first non-minimized KeePassXC/KeePassX window if available.
    #   - FlClash:
    #       Optional. If running but hidden, activate it before capture.
    #       Use visible non-minimized FlClash/Thaw windows if available.
    #
    # Creation rule:
    #   The workspace is only created if at least one of the following exists:
    #     - Warp
    #     - SmartGit
    #     - KeePassXC
    #     - FlClash
    #
    # Layout:
    #   - Warp     -> upper 2/3 of the screen
    #   - SmartGit -> fixed absolute position and size
    #   - KeePassXC -> moved to the same control space without forcing bounds
    #   - FlClash  -> lower 1/3 of the screen
    #
    # Notes:
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It retargets the label when the existing space has non-control windows.
    #   - It retries standard app-key windows once if they do not land on target.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    set -l label coding_control
    set -l flclash_app (workspace_app_name flclash)
    set -l flclash_apps_json (workspace_app_names_json flclash thaw)
    set -l control_app_regex (workspace_app_regex warp smartgit keepassx flclash thaw)
    or return 1

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

    set -l warp (workspace_find_app_key_window --app-key warp --caller $label)
    set -l warp_status $status
    if test "$warp_status" -eq 1
        return 1
    end

    set -l smartgit
    set -l smartgit_status 0
    set -l smartgit_fallback_window
    set -l smartgit_fallback_space
    set -l smartgit_fallback_display

    set -l smartgit_info (echo $windows_json | workspace_app_key_window_info --app-key smartgit --movable)
    if test $status -ne 0
        return 1
    end

    if test -n "$smartgit_info"
        set -l smartgit_parts (string split \t -- "$smartgit_info")
        set smartgit $smartgit_parts[1]
    else
        set -l smartgit_fallback_info (echo $windows_json | workspace_app_key_window_info --app-key smartgit --unmovable)
        if test $status -ne 0
            return 1
        end

        if test -n "$smartgit_fallback_info"
            set smartgit_status 2
            set -l smartgit_fallback_parts (string split \t -- "$smartgit_fallback_info")
            set smartgit_fallback_window $smartgit_fallback_parts[1]
            set smartgit_fallback_space $smartgit_fallback_parts[2]
            set smartgit_fallback_display $smartgit_fallback_parts[3]

            if test -z "$smartgit_fallback_window" -o -z "$smartgit_fallback_space" -o -z "$smartgit_fallback_display"
                echo "[WARN] $label found SmartGit, but its fallback space metadata was incomplete" >&2
                return 1
            end
        end
    end

    set -l keepassx (workspace_find_app_key_window --app-key keepassx --caller $label)
    set -l keepassx_status $status
    if test "$keepassx_status" -eq 1
        return 1
    end

    set -l flclash (echo $windows_json | ws_jq -r --argjson apps "$flclash_apps_json" '
        .[]
        | select(.app as $app | $apps | index($app))
        | select(.["is-minimized"]==false)
        | select(.["is-visible"]==true)
        | .id
    ')

    # Do not create the workspace if neither helper window exists
    if test -z "$warp" -a -z "$smartgit" -a -z "$smartgit_fallback_window" -a -z "$keepassx" -a -z "$flclash"
        if test "$warp_status" -eq 2 -o "$smartgit_status" -eq 2 -o "$keepassx_status" -eq 2
            return 1
        end

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
    set -l smartgit_space_fallback_used 0
    set -l target_space

    if test -n "$smartgit_fallback_space"
        set target_space (workspace_focus_space_fallback \
            --label $label \
            --caller $label \
            --space $smartgit_fallback_space \
            --source-display $smartgit_fallback_display \
            --target-display $target_display \
            --layout float \
            --phase smartgit-space-fallback)
        or return 1

        workspace_evict_non_owned_windows_from_space \
            --caller $label \
            --space $target_space \
            --target-display $target_display \
            --allowed-app-regex "$control_app_regex"
        or return 1

        set smartgit_space_fallback_used 1
    else
        set target_space (find_or_create_labeled_space $label $target_display)
        if test -z "$target_space"
            return 1
        end

        set target_space (workspace_retarget_contaminated_space \
            $label \
            $label \
            $target_space \
            $target_display \
            "$control_app_regex")
        or return 1

        workspace_focus_labeled_space $label $target_space $target_display float
        or return 1
    end

    # -------------------------------------------------------------------------
    # 5. First-pass move
    # -------------------------------------------------------------------------
    set -l warp_initial $warp
    set -l smartgit_initial $smartgit
    set -l keepassx_initial $keepassx

    if test "$smartgit_space_fallback_used" -eq 1
        ws_move_windows_to_space $target_space $warp $keepassx $flclash
    else
        ws_move_windows_to_space $target_space $warp $smartgit $keepassx $flclash
    end

    # -------------------------------------------------------------------------
    # 6. Final capture on target space
    # -------------------------------------------------------------------------
    set -l windows_json_final (ws_query_windows "coding_control" final); or return 1

    set warp (workspace_find_app_key_window --app-key warp --caller $label --space $target_space --no-refresh --target-only)
    set smartgit (workspace_find_app_key_window --app-key smartgit --caller $label --space $target_space --no-refresh --target-only)
    set keepassx (workspace_find_app_key_window --app-key keepassx --caller $label --space $target_space --no-refresh --target-only)

    if test "$smartgit_space_fallback_used" -eq 1
        set -l smartgit_target_windows (echo $windows_json_final | workspace_app_key_windows --app-key smartgit --space $target_space)
        or return 1
        set smartgit $smartgit_target_windows[1]
        if test -z "$smartgit"
            set smartgit $smartgit_fallback_window
        end
    end

    if test -z "$warp" -a -n "$warp_initial"
        set warp (workspace_find_app_key_window --app-key warp --caller $label)
        set warp_status $status
        if test "$warp_status" -eq 1
            return 1
        end

        if test -n "$warp"
            ws_move_windows_to_space $target_space $warp
            set warp (workspace_find_app_key_window --app-key warp --caller $label --space $target_space --no-refresh --target-only)
        end
    end

    if test "$smartgit_space_fallback_used" -ne 1 -a -z "$smartgit" -a -n "$smartgit_initial"
        set smartgit (workspace_find_app_key_window --app-key smartgit --caller $label)
        set smartgit_status $status
        if test "$smartgit_status" -eq 1
            return 1
        end

        if test -n "$smartgit"
            ws_move_windows_to_space $target_space $smartgit
            set smartgit (workspace_find_app_key_window --app-key smartgit --caller $label --space $target_space --no-refresh --target-only)
        end
    end

    if test -z "$keepassx" -a -n "$keepassx_initial"
        set keepassx (workspace_find_app_key_window --app-key keepassx --caller $label)
        set keepassx_status $status
        if test "$keepassx_status" -eq 1
            return 1
        end

        if test -n "$keepassx"
            ws_move_windows_to_space $target_space $keepassx
            set keepassx (workspace_find_app_key_window --app-key keepassx --caller $label --space $target_space --no-refresh --target-only)
        end
    end

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
        if test "$smartgit_space_fallback_used" -eq 1
            workspace_apply_app_key_absolute_bounds \
                --app-key smartgit \
                --x 300 \
                --y 60 \
                --width 1200 \
                --height 1040 \
                --caller $label
        else
            ws_window $smartgit --move abs:300:60
            ws_window $smartgit --resize abs:1200:1040
        end
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

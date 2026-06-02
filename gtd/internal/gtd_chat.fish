function gtd_chat --description "Fast GTD chat workspace layout on workspace primary display"
    argparse dry-run -- $argv
    or return 1

    if set -q _flag_dry_run
        set -l dingtalk_apps (string join '|' (workspace_app_names dingtalk))
        printf "dry_run=gtd_chat\n"
        printf "label=%s\n" gtd_chat
        printf "display=%s\n" primary
        printf "apps=%s,%s,%s,%s,%s\n" (workspace_app_name wechat) (workspace_app_name keybase) "$dingtalk_apps" (workspace_app_name messages) (workspace_app_name whatsapp)
        return 0
    end

    # -------------------------------------------------------------------------
    # Workspace:
    #   gtd_chat
    #
    # Purpose:
    #   Collect chat-related applications onto the GTD chat workspace on the
    #   workspace primary display and apply the standard chat layout.
    #
    # Target display:
    #   Workspace primary display only.
    #
    # Managed apps:
    #   - WeChat
    #   - Keybase
    #   - 钉钉 / DingTalk
    #   - Messages
    #   - WhatsApp
    #
    # Layout:
    #   - Keybase  -> upper-left
    #   - WeChat   -> lower-left
    #   - 钉钉      -> upper-right
    #   - Messages -> lower-right
    #   - WhatsApp -> centered, moderate size
    #
    # Notes:
    #   - The function is re-runnable.
    #   - It reuses an existing labeled space when possible.
    #   - It retargets the label when the existing space has non-chat windows.
    #   - It retries stable chat apps once if they do not land on target.
    #   - WhatsApp is treated as optional and move failures are tolerated.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    set -l label gtd_chat
    set -l dingtalk_regex (workspace_app_regex dingtalk)
    set -l dingtalk_apps_json (workspace_app_names_json dingtalk)
    or return 1
    set -l messages_app (workspace_app_name messages)
    set -l whatsapp_app (workspace_app_name whatsapp)
    set -l chat_app_regex (workspace_app_regex wechat keybase dingtalk messages whatsapp)
    or return 1

    # 1. first capture
    #    At least one chat app must exist before creating the workspace.
    set -l windows_json (ws_query_windows gtd_chat initial); or return 1

    set -l wechat (workspace_find_app_key_window --app-key wechat --caller $label)
    set -l wechat_status $status
    if test "$wechat_status" -eq 1
        return 1
    end

    set -l keybase (workspace_find_app_key_window --app-key keybase --caller $label)
    set -l keybase_status $status
    if test "$keybase_status" -eq 1
        return 1
    end

    set -l dingtalk_space_fallback_used 0
    set -l dingtalk_status 0
    set -l dingtalk
    set -l dingtalk_fallback_window
    set -l dingtalk_fallback_space
    set -l dingtalk_fallback_display

    set -l dingtalk_initial_info (echo $windows_json | workspace_app_key_window_info --app-key dingtalk)
    if test $status -ne 0
        return 1
    end

    if test -n "$dingtalk_initial_info"
        set -l dingtalk_initial_parts (string split \t -- "$dingtalk_initial_info")
        if test "$dingtalk_initial_parts[4]" = true
            set dingtalk $dingtalk_initial_parts[1]
            rm -f /tmp/workspace-ws-window-bad/$dingtalk 2>/dev/null
        else
            set dingtalk_status 2
            set dingtalk_fallback_window $dingtalk_initial_parts[1]
            set dingtalk_fallback_space $dingtalk_initial_parts[2]
            set dingtalk_fallback_display $dingtalk_initial_parts[3]
        end
    else
        set dingtalk (workspace_find_app_key_window --app-key dingtalk --caller $label --quiet-unmovable)
        set dingtalk_status $status
        if test "$dingtalk_status" -eq 1
            return 1
        end
    end

    if test -z "$dingtalk" -a "$dingtalk_status" -eq 2 -a -z "$dingtalk_fallback_window"
        set -l dingtalk_fallback_info (workspace_app_key_space_fallback_info \
            --app-key dingtalk \
            --caller $label \
            --phase dingtalk_space_fallback)
        set -l dingtalk_fallback_status $status

        if test "$dingtalk_fallback_status" -eq 1
            return 1
        end

        if test -z "$dingtalk_fallback_info"
            echo "[WARN] $label found DingTalk, but could not identify a DingTalk space fallback" >&2
            return 1
        end

        set -l dingtalk_fallback_parts (string split \t -- "$dingtalk_fallback_info")
        set dingtalk_fallback_window $dingtalk_fallback_parts[1]
        set dingtalk_fallback_space $dingtalk_fallback_parts[2]
        set dingtalk_fallback_display $dingtalk_fallback_parts[3]

        if test -z "$dingtalk_fallback_window" -o -z "$dingtalk_fallback_space" -o -z "$dingtalk_fallback_display"
            echo "[WARN] $label found DingTalk, but its fallback space metadata was incomplete" >&2
            return 1
        end
    end

    set -l messages (workspace_find_app_key_window --app-key messages --caller $label)
    set -l messages_status $status
    if test "$messages_status" -eq 1
        return 1
    end

    set -l whatsapp (echo $windows_json | ws_find_window "$whatsapp_app")

    if test -z "$wechat" -a -z "$keybase" -a -z "$dingtalk" -a -z "$dingtalk_fallback_window" -a -z "$messages" -a -z "$whatsapp"
        if test "$wechat_status" -eq 2 -o "$keybase_status" -eq 2 -o "$dingtalk_status" -eq 2 -o "$messages_status" -eq 2
            return 1
        end

        destroy_empty_labeled_space $label

        return 0
    end

    # 2. resolve target display
    set -l target_display (resolve_workspace_primary_display)

    # 3. prepare target space
    set -l target_space

    if test -n "$dingtalk_fallback_space"
        set dingtalk_space_fallback_used 1
        set target_space $dingtalk_fallback_space
        set dingtalk $dingtalk_fallback_window

        set target_space (workspace_focus_space_fallback \
            --label $label \
            --space $target_space \
            --source-display $dingtalk_fallback_display \
            --target-display $target_display \
            --layout float \
            --phase dingtalk-space-fallback)
        or return 1

        workspace_evict_non_owned_windows_from_space \
            --caller $label \
            --space $target_space \
            --target-display $target_display \
            --allowed-app-regex "$chat_app_regex"
        or return 1
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
            "$chat_app_regex")
        or return 1

        workspace_focus_labeled_space $label $target_space $target_display float
        or return 1
    end

    # 4a. move stable chat apps
    if test "$dingtalk_space_fallback_used" -eq 1
        ws_move_windows_to_space $target_space $wechat $keybase $messages
    else
        ws_move_windows_to_space $target_space $wechat $keybase $dingtalk $messages
    end

    # 4b. move WhatsApp separately; tolerate move failures
    if test -n "$whatsapp"
        ws_window $whatsapp --space $target_space >/dev/null 2>&1
    end

    # 5. final capture on target space
    set -l windows_json_final (ws_query_windows gtd_chat final); or return 1

    set wechat (workspace_find_app_key_window --app-key wechat --caller $label --space $target_space --no-refresh --target-only)

    set keybase (workspace_find_app_key_window --app-key keybase --caller $label --space $target_space --no-refresh --target-only)

    if test "$dingtalk_space_fallback_used" -eq 1
        set dingtalk (echo $windows_json_final | ws_jq -r --argjson apps "$dingtalk_apps_json" --argjson s $target_space '
            first(
                .[]
                | select(.app as $app | $apps | index($app))
                | select(.space==$s)
                | select(.["is-minimized"]==false)
                | .id
            ) // empty
        ')
    else
        set dingtalk (echo $windows_json_final | ws_find_window --app-regex "$dingtalk_regex" --space $target_space)
    end

    set messages (echo $windows_json_final | ws_find_window "$messages_app" --space $target_space)

    set whatsapp (echo $windows_json_final | ws_find_window "$whatsapp_app" --space $target_space)

    if test -z "$wechat"
        set wechat (workspace_find_app_key_window --app-key wechat --caller $label)
        set wechat_status $status
        if test "$wechat_status" -eq 1
            return 1
        end

        if test -n "$wechat"
            ws_move_windows_to_space $target_space $wechat
            set windows_json_final (ws_query_windows gtd_chat final_wechat_retry); or return 1
            set wechat (workspace_find_app_key_window --app-key wechat --caller $label --space $target_space --no-refresh --target-only)
        end
    end

    if test -z "$keybase"
        set keybase (workspace_find_app_key_window --app-key keybase --caller $label)
        set keybase_status $status
        if test "$keybase_status" -eq 1
            return 1
        end

        if test -n "$keybase"
            ws_move_windows_to_space $target_space $keybase
            set windows_json_final (ws_query_windows gtd_chat final_keybase_retry); or return 1
            set keybase (workspace_find_app_key_window --app-key keybase --caller $label --space $target_space --no-refresh --target-only)
        end
    end

    if test -z "$dingtalk" -a "$dingtalk_space_fallback_used" -ne 1
        set dingtalk (workspace_find_app_key_window --app-key dingtalk --caller $label)
        set dingtalk_status $status
        if test "$dingtalk_status" -eq 1
            return 1
        end

        if test -n "$dingtalk"
            ws_move_windows_to_space $target_space $dingtalk
            set windows_json_final (ws_query_windows gtd_chat final_dingtalk_retry); or return 1
            set dingtalk (echo $windows_json_final | ws_find_window --app-regex "$dingtalk_regex" --space $target_space)
        end
    end

    if test -z "$messages"
        set messages (workspace_find_app_key_window --app-key messages --caller $label)
        set messages_status $status
        if test "$messages_status" -eq 1
            return 1
        end

        if test -n "$messages"
            ws_move_windows_to_space $target_space $messages
            set windows_json_final (ws_query_windows gtd_chat final_messages_retry); or return 1
            set messages (echo $windows_json_final | ws_find_window "$messages_app" --space $target_space)
        end
    end

    # 7. final layout
    if test -n "$keybase"
        ws_window $keybase --grid 2:2:0:0:1:1
    end

    if test -n "$wechat"
        ws_window $wechat --grid 2:2:0:1:1:1
    end

    if test -n "$dingtalk"
        if test "$dingtalk_space_fallback_used" -eq 1
            workspace_apply_app_key_grid_bounds \
                --app-key dingtalk \
                --display $target_display \
                --grid 2:2:1:0:1:1 \
                --caller $label
        else
            ws_window $dingtalk --grid 2:2:1:0:1:1
        end
    end

    if test -n "$messages"
        ws_window $messages --grid 2:2:1:1:1:1
    end

    if test -n "$whatsapp"
        ws_window $whatsapp --move abs:458:190
        ws_window $whatsapp --resize abs:885:560
    end

    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_space
end

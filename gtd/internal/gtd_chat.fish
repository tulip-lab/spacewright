function gtd_chat --description "Fast GTD chat workspace layout on workspace primary display"
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
    #   - It moves only the initially captured window IDs.
    #   - WhatsApp is treated as optional and move failures are tolerated.
    #   - It clears unlabeled empty spaces on the target display at the end.
    # -------------------------------------------------------------------------

    set -l label gtd_chat

    # 1. first capture
    #    At least one chat app must exist before creating the workspace.
    set -l windows_json (ws_query_windows gtd_chat initial); or return 1

    set -l wechat (echo $windows_json | ws_find_window "WeChat")

    set -l keybase (echo $windows_json | ws_find_window "Keybase")

    set -l dingtalk (echo $windows_json | ws_find_window --app-regex '^(钉钉|DingTalk)$')

    set -l messages (echo $windows_json | ws_find_window "Messages")

    set -l whatsapp (echo $windows_json | ws_find_window --app-regex 'WhatsApp$')

    if test -z "$wechat" -a -z "$keybase" -a -z "$dingtalk" -a -z "$messages" -a -z "$whatsapp"
        destroy_empty_labeled_space $label

        return 0
    end

    # 2. resolve target display
    set -l target_display (resolve_workspace_primary_display)

    # 3. prepare target space
    set -l target_space (workspace_prepare_labeled_space $label $target_display float)
    or return 1

    # 4a. move stable chat apps
    ws_move_windows_to_space $target_space $wechat $keybase $dingtalk $messages

    # 4b. move WhatsApp separately; tolerate move failures
    if test -n "$whatsapp"
        ws_window $whatsapp --space $target_space >/dev/null 2>&1
    end

    # 5. final capture on target space
    set -l windows_json_final (ws_query_windows gtd_chat final); or return 1

    set wechat (echo $windows_json_final | ws_find_window "WeChat" --space $target_space)

    set keybase (echo $windows_json_final | ws_find_window "Keybase" --space $target_space)

    set dingtalk (echo $windows_json_final | ws_find_window --app-regex '^(钉钉|DingTalk)$' --space $target_space)

    set messages (echo $windows_json_final | ws_find_window "Messages" --space $target_space)

    set whatsapp (echo $windows_json_final | ws_find_window --app-regex 'WhatsApp$' --space $target_space)

    # 7. final layout
    if test -n "$keybase"
        ws_window $keybase --grid 2:2:0:0:1:1
    end

    if test -n "$wechat"
        ws_window $wechat --grid 2:2:0:1:1:1
    end

    if test -n "$dingtalk"
        ws_window $dingtalk --grid 2:2:1:0:1:1
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

function gtd_chat --description "Fast GTD chat workspace layout on internal display"
    set -l label gtd_chat
    set -l internal_uuid "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    # 1. resolve target display
    set -l target_display (resolve_target_display $internal_uuid 1)

    # 2. find or create target space
    set -l target_space (find_or_create_labeled_space $label $target_display)
    if test -z "$target_space"
        return 1
    end

    # 3. normalize target space
    prepare_labeled_space $target_space $label float

    ws_focus_display $target_display
    sleep 0.15
    ws_focus_space $target_space
    sleep 0.15

    # 4. first capture
    set -l windows_json (yabai -m query --windows)

    set -l wechat (echo $windows_json | jq -r '.[] | select(.app=="WeChat" and .["is-minimized"]==false) | .id' | head -n 1)
    set -l keybase (echo $windows_json | jq -r '.[] | select(.app=="Keybase" and .["is-minimized"]==false) | .id' | head -n 1)
    set -l dingtalk (echo $windows_json | jq -r '.[] | select((.app=="钉钉" or .app=="DingTalk") and .["is-minimized"]==false) | .id' | head -n 1)
    set -l messages (echo $windows_json | jq -r '.[] | select(.app=="Messages" and .["is-minimized"]==false) | .id' | head -n 1)
    set -l whatsapp (echo $windows_json | jq -r '.[] | select((.app=="‎WhatsApp" or .app=="WhatsApp") and .["is-minimized"]==false) | .id' | head -n 1)

    for wid in $wechat $keybase $dingtalk $messages $whatsapp
        if test -n "$wid"
            yabai -m window $wid --space $target_space
        end
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # 5. retry capture
    set -l windows_json_retry (yabai -m query --windows)

    set -l wechat_retry (echo $windows_json_retry | jq -r --argjson s $target_space '.[] | select(.app=="WeChat" and .space!=$s and .["is-minimized"]==false) | .id' | head -n 1)
    set -l keybase_retry (echo $windows_json_retry | jq -r --argjson s $target_space '.[] | select(.app=="Keybase" and .space!=$s and .["is-minimized"]==false) | .id' | head -n 1)
    set -l dingtalk_retry (echo $windows_json_retry | jq -r --argjson s $target_space '.[] | select((.app=="钉钉" or .app=="DingTalk") and .space!=$s and .["is-minimized"]==false) | .id' | head -n 1)
    set -l messages_retry (echo $windows_json_retry | jq -r --argjson s $target_space '.[] | select(.app=="Messages" and .space!=$s and .["is-minimized"]==false) | .id' | head -n 1)
    set -l whatsapp_retry (echo $windows_json_retry | jq -r --argjson s $target_space '.[] | select((.app=="‎WhatsApp" or .app=="WhatsApp") and .space!=$s and .["is-minimized"]==false) | .id' | head -n 1)

    for wid in $wechat_retry $keybase_retry $dingtalk_retry $messages_retry $whatsapp_retry
        if test -n "$wid"
            yabai -m window $wid --space $target_space
        end
    end

    sleep 0.25
    ws_focus_space $target_space
    sleep 0.15

    # 6. final capture on target space
    set -l windows_json_final (yabai -m query --windows)

    set wechat (echo $windows_json_final | jq -r --argjson s $target_space '.[] | select(.app=="WeChat" and .space==$s and .["is-minimized"]==false) | .id' | head -n 1)
    set keybase (echo $windows_json_final | jq -r --argjson s $target_space '.[] | select(.app=="Keybase" and .space==$s and .["is-minimized"]==false) | .id' | head -n 1)
    set dingtalk (echo $windows_json_final | jq -r --argjson s $target_space '.[] | select((.app=="钉钉" or .app=="DingTalk") and .space==$s and .["is-minimized"]==false) | .id' | head -n 1)
    set messages (echo $windows_json_final | jq -r --argjson s $target_space '.[] | select(.app=="Messages" and .space==$s and .["is-minimized"]==false) | .id' | head -n 1)
    set whatsapp (echo $windows_json_final | jq -r --argjson s $target_space '.[] | select((.app=="‎WhatsApp" or .app=="WhatsApp") and .space==$s and .["is-minimized"]==false) | .id' | head -n 1)

    # 7. final layout
    if test -n "$keybase"
        yabai -m window $keybase --grid 2:2:0:0:1:1
    end
    if test -n "$wechat"
        yabai -m window $wechat --grid 2:2:0:1:1:1
    end
    if test -n "$dingtalk"
        yabai -m window $dingtalk --grid 2:2:1:0:1:1
    end
    if test -n "$messages"
        yabai -m window $messages --grid 2:2:1:1:1:1
    end

    if test -n "$whatsapp"
        yabai -m window $whatsapp --move abs:458:190
        yabai -m window $whatsapp --resize abs:885:560
    end

    ws_focus_space $target_space
    cleanup_unlabeled_empty_spaces $target_display
end
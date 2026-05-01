function gtd_chat
    set label gtd_chat
    set internal_uuid "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    set target_display (yabai -m query --displays | jq -r ".[] | select(.uuid==\"$internal_uuid\") | .index" | head -n 1)
    if test -z "$target_display"
        set target_display 1
    end

    # 优先复用已有 labeled space
    set target_space (yabai -m query --spaces | jq -r ".[] | select(.label==\"$label\") | .index" | head -n 1)

    # 如果没有，才创建
    if test -z "$target_space"
        focus_display_if_needed $target_display
        sleep 0.4

        yabai -m space --create
        sleep 0.8

        set target_space (yabai -m query --spaces | jq -r ".[] | select(.display==$target_display and .label==\"\") | .index" | tail -n 1)

        yabai -m space $target_space --label $label
        yabai -m space $target_space --layout float
    end

    focus_space_if_needed $target_space
    sleep 0.5

    set wechat   (yabai -m query --windows | jq -r '.[] | select(.app=="WeChat" and .["is-minimized"]==false) | .id' | head -n 1)
    set keybase  (yabai -m query --windows | jq -r '.[] | select(.app=="Keybase" and .["is-minimized"]==false) | .id' | head -n 1)
    set dingtalk (yabai -m query --windows | jq -r '.[] | select(.app=="DingTalk" and .["is-minimized"]==false) | .id' | head -n 1)
    set messages (yabai -m query --windows | jq -r '.[] | select(.app=="Messages" and .["is-minimized"]==false) | .id' | head -n 1)
    set whatsapp (yabai -m query --windows | jq -r '.[] | select((.app=="‎WhatsApp" or .app=="WhatsApp") and .["is-minimized"]==false) | .id' | head -n 1)

    if test -n "$wechat"
        yabai -m window $wechat --space $target_space
    end
    if test -n "$keybase"
        yabai -m window $keybase --space $target_space
    end
    if test -n "$dingtalk"
        yabai -m window $dingtalk --space $target_space
    end
    if test -n "$messages"
        yabai -m window $messages --space $target_space
    end
    if test -n "$whatsapp"
        yabai -m window $whatsapp --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    set wechat_retry   (yabai -m query --windows | jq -r ".[] | select(.app==\"WeChat\" and .space!=$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)
    set keybase_retry  (yabai -m query --windows | jq -r ".[] | select(.app==\"Keybase\" and .space!=$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)
    set dingtalk_retry (yabai -m query --windows | jq -r ".[] | select(.app==\"DingTalk\" and .space!=$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)
    set messages_retry (yabai -m query --windows | jq -r ".[] | select(.app==\"Messages\" and .space!=$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)
    set whatsapp_retry (yabai -m query --windows | jq -r ".[] | select((.app==\"‎WhatsApp\" or .app==\"WhatsApp\") and .space!=$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)

    if test -n "$wechat_retry"
        yabai -m window $wechat_retry --space $target_space
    end
    if test -n "$keybase_retry"
        yabai -m window $keybase_retry --space $target_space
    end
    if test -n "$dingtalk_retry"
        yabai -m window $dingtalk_retry --space $target_space
    end
    if test -n "$messages_retry"
        yabai -m window $messages_retry --space $target_space
    end
    if test -n "$whatsapp_retry"
        yabai -m window $whatsapp_retry --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    set wechat   (yabai -m query --windows | jq -r ".[] | select(.app==\"WeChat\" and .space==$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)
    set keybase  (yabai -m query --windows | jq -r ".[] | select(.app==\"Keybase\" and .space==$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)
    set dingtalk (yabai -m query --windows | jq -r ".[] | select(.app==\"DingTalk\" and .space==$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)
    set messages (yabai -m query --windows | jq -r ".[] | select(.app==\"Messages\" and .space==$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)
    set whatsapp (yabai -m query --windows | jq -r ".[] | select((.app==\"‎WhatsApp\" or .app==\"WhatsApp\") and .space==$target_space and .[\"is-minimized\"]==false) | .id" | head -n 1)

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

    focus_space_if_needed $target_space
end
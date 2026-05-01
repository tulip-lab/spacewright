function coding_control
    set label coding_control
    set internal_uuid "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    # 先检查控制区是否至少有一个核心辅助 app
    set warp (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Warp")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set smartgit (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="SmartGit")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    # 如果 Warp 和 SmartGit 都不存在，就不创建 coding_control
    if test -z "$warp" -a -z "$smartgit"
        return
    end

    # 选择内置屏
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

    # 第一轮搬运
    if test -n "$warp"
        yabai -m window $warp --space $target_space
    end
    if test -n "$smartgit"
        yabai -m window $smartgit --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 第二轮校验与补搬运
    set warp_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Warp\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set smartgit_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"SmartGit\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    if test -n "$warp_retry"
        yabai -m window $warp_retry --space $target_space
    end
    if test -n "$smartgit_retry"
        yabai -m window $smartgit_retry --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 在目标 space 内重新获取窗口 id
    set warp (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Warp\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set smartgit (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"SmartGit\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    # 保持当前确认布局：
    # Warp 占屏幕上方 2/3 区域
    # SmartGit 使用绝对位置和尺寸
    if test -n "$warp"
        yabai -m window $warp --grid 3:1:0:0:1:2
    end
    if test -n "$smartgit"
        yabai -m window $smartgit --move abs:300:60
        yabai -m window $smartgit --resize abs:1200:1040
    end

    focus_space_if_needed $target_space
end
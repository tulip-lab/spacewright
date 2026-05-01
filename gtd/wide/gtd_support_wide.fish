function gtd_support_wide
    # 进入 wide 模式前，先清理已经空掉的 GTD tall spaces
    gtd_cleanup_tall_spaces

    set label gtd_support_wide
    set internal_uuid "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    # 选择外接屏；如果没有外接屏，则回退到内置屏
    set target_display (yabai -m query --displays | jq -r ".[] | select(.uuid!=\"$internal_uuid\") | .index" | head -n 1)
    if test -z "$target_display"
        set target_display (yabai -m query --displays | jq -r ".[] | select(.uuid==\"$internal_uuid\") | .index" | head -n 1)
    end

    # 优先复用已有 labeled space
    set target_space (yabai -m query --spaces | jq -r ".[] | select(.label==\"$label\") | .index" | head -n 1)

    # 不存在时才创建
    if test -z "$target_space"
        focus_display_if_needed $target_display
        sleep 0.4

        yabai -m space --create
        sleep 0.8

        set target_space (yabai -m query --spaces | jq -r ".[] | select(.display==$target_display and .label==\"\") | .index" | tail -n 1)

        yabai -m space $target_space --label $label
        yabai -m space $target_space --layout float
    end

    # Notes：优先取标题非空的主窗口
    set notes (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Notes")
        | select(.["is-minimized"]==false)
        | select(.title != null and .title != "")
        | .id
    ' | head -n 1)
    if test -z "$notes"
        set notes (yabai -m query --windows | jq -r '
            .[]
            | select(.app=="Notes")
            | select(.["is-minimized"]==false)
            | .id
        ' | head -n 1)
    end

    # Dia：优先取标题非空且不是 New Tab 的主窗口
    set dia (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Dia")
        | select(.["is-minimized"]==false)
        | select(.title != null and .title != "")
        | select((.title | ascii_downcase | contains("new tab")) | not)
        | .id
    ' | head -n 1)
    if test -z "$dia"
        set dia (yabai -m query --windows | jq -r '
            .[]
            | select(.app=="Dia")
            | select(.["is-minimized"]==false)
            | .id
        ' | head -n 1)
    end

    # 第一轮搬运
    if test -n "$notes"
        yabai -m window $notes --space $target_space
    end
    if test -n "$dia"
        yabai -m window $dia --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 第二轮校验与补搬运
    set notes_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Notes\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | select(.title != null and .title != \"\")
        | .id
    " | head -n 1)
    if test -z "$notes_retry"
        set notes_retry (yabai -m query --windows | jq -r "
            .[]
            | select(.app==\"Notes\")
            | select(.space!=$target_space)
            | select(.[\"is-minimized\"]==false)
            | .id
        " | head -n 1)
    end

    set dia_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Dia\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | select(.title != null and .title != \"\")
        | select((.title | ascii_downcase | contains(\"new tab\")) | not)
        | .id
    " | head -n 1)
    if test -z "$dia_retry"
        set dia_retry (yabai -m query --windows | jq -r "
            .[]
            | select(.app==\"Dia\")
            | select(.space!=$target_space)
            | select(.[\"is-minimized\"]==false)
            | .id
        " | head -n 1)
    end

    if test -n "$notes_retry"
        yabai -m window $notes_retry --space $target_space
    end
    if test -n "$dia_retry"
        yabai -m window $dia_retry --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 在目标 space 内重新获取窗口 id
    set notes (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Notes\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | select(.title != null and .title != \"\")
        | .id
    " | head -n 1)
    if test -z "$notes"
        set notes (yabai -m query --windows | jq -r "
            .[]
            | select(.app==\"Notes\")
            | select(.space==$target_space)
            | select(.[\"is-minimized\"]==false)
            | .id
        " | head -n 1)
    end

    set dia (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Dia\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | select(.title != null and .title != \"\")
        | select((.title | ascii_downcase | contains(\"new tab\")) | not)
        | .id
    " | head -n 1)
    if test -z "$dia"
        set dia (yabai -m query --windows | jq -r "
            .[]
            | select(.app==\"Dia\")
            | select(.space==$target_space)
            | select(.[\"is-minimized\"]==false)
            | .id
        " | head -n 1)
    end

    # 保持原来的布局：Dia 右 3/5，Notes 左 2/5
    if test -n "$dia"
        yabai -m window $dia --grid 1:5:2:0:3:1
    end
    if test -n "$notes"
        yabai -m window $notes --grid 1:5:0:0:2:1
    end

    focus_space_if_needed $target_space
end
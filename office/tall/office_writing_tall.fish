function office_writing_tall
    # 进入 tall 模式前，先清理已经空掉的 Office wide spaces
    office_cleanup_wide_spaces

    set label office_writing_tall
    set internal_uuid "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    # 先找 Word；如果没有，就不创建 office_writing_tall
    set word_window (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Microsoft Word")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -z "$word_window"
        return
    end

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

    # 第一轮搬运
    yabai -m window $word_window --space $target_space

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 第二轮校验与补搬运
    set word_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Microsoft Word\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    if test -n "$word_retry"
        yabai -m window $word_retry --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 在目标 space 内重新获取窗口 id
    set word_window (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Microsoft Word\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    # 保持原来的布局：Word 在下半 1/2
    if test -n "$word_window"
        yabai -m window $word_window --grid 2:1:0:1:1:1
    end

    focus_space_if_needed $target_space
end
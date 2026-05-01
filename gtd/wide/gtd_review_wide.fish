function gtd_review_wide
    # 进入 wide 模式前，先清理已经空掉的 GTD tall spaces
    gtd_cleanup_tall_spaces

    set label gtd_review_wide
    set internal_uuid "37D8832A-2D66-02CA-B9F7-8F30A301B230"

    # 先找 Preview；如果没有，就不创建 gtd_review_wide
    set preview (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Preview")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -z "$preview"
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

    # 其余 review 场景辅助窗口
    set finder (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Finder")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set chatgpt (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="ChatGPT")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    # Notes 优先选择 title 非空的主窗口
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

    # 第一轮搬运
    if test -n "$finder"
        yabai -m window $finder --space $target_space
    end
    yabai -m window $preview --space $target_space
    if test -n "$chatgpt"
        yabai -m window $chatgpt --space $target_space
    end
    if test -n "$notes"
        yabai -m window $notes --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 第二轮校验与补搬运
    set finder_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Finder\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set preview_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Preview\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set chatgpt_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"ChatGPT\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

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

    if test -n "$finder_retry"
        yabai -m window $finder_retry --space $target_space
    end
    if test -n "$preview_retry"
        yabai -m window $preview_retry --space $target_space
    end
    if test -n "$chatgpt_retry"
        yabai -m window $chatgpt_retry --space $target_space
    end
    if test -n "$notes_retry"
        yabai -m window $notes_retry --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 在目标 space 内重新获取窗口 id
    set finder (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Finder\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set preview (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Preview\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set chatgpt (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"ChatGPT\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

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

    # 左 1/4 Finder；中 3/8 Preview；右 3/8 上 ChatGPT 下 Notes
    if test -n "$finder"
        yabai -m window $finder --grid 2:8:0:0:2:2
    end
    if test -n "$preview"
        yabai -m window $preview --grid 2:8:2:0:3:2
    end
    if test -n "$chatgpt"
        yabai -m window $chatgpt --grid 2:8:5:0:3:1
    end
    if test -n "$notes"
        yabai -m window $notes --grid 2:8:5:1:3:1
    end

    focus_space_if_needed $target_space
end
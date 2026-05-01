function gtd_meeting_tall
    # 进入 tall 模式前，先清理已经空掉的 GTD wide spaces
    gtd_cleanup_wide_spaces

    set label gtd_meeting_tall
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

    # 选择 Outlook、Zoom、Teams 主窗口
    set out (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Microsoft Outlook" and .["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set zoom (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="zoom.us" and .["is-minimized"]==false)
        | select((.title | ascii_downcase | contains("meeting")) | not)
        | select((.title | ascii_downcase | contains("video"))   | not)
        | select((.title | ascii_downcase | contains("share"))   | not)
        | select((.title | ascii_downcase | contains("screen"))  | not)
        | select((.title | ascii_downcase | contains("mini"))    | not)
        | .id
    ' | head -n 1)

    set teams (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Microsoft Teams" and .["is-minimized"]==false)
        | select((.title | ascii_downcase | contains("meeting")) | not)
        | select((.title | ascii_downcase | contains("video"))   | not)
        | select((.title | ascii_downcase | contains("call"))    | not)
        | select((.title | ascii_downcase | contains("share"))   | not)
        | select((.title | ascii_downcase | contains("screen"))  | not)
        | select((.title | ascii_downcase | contains("mini"))    | not)
        | .id
    ' | head -n 1)

    # 第一轮搬运
    if test -n "$out"
        yabai -m window $out --space $target_space
    end
    if test -n "$zoom"
        yabai -m window $zoom --space $target_space
    end
    if test -n "$teams"
        yabai -m window $teams --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 第二轮校验与补搬运
    set out_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Microsoft Outlook\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set zoom_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"zoom.us\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | select((.title | ascii_downcase | contains(\"meeting\")) | not)
        | select((.title | ascii_downcase | contains(\"video\"))   | not)
        | select((.title | ascii_downcase | contains(\"share\"))   | not)
        | select((.title | ascii_downcase | contains(\"screen\"))  | not)
        | select((.title | ascii_downcase | contains(\"mini\"))    | not)
        | .id
    " | head -n 1)

    set teams_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Microsoft Teams\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | select((.title | ascii_downcase | contains(\"meeting\")) | not)
        | select((.title | ascii_downcase | contains(\"video\"))   | not)
        | select((.title | ascii_downcase | contains(\"call\"))    | not)
        | select((.title | ascii_downcase | contains(\"share\"))   | not)
        | select((.title | ascii_downcase | contains(\"screen\"))  | not)
        | select((.title | ascii_downcase | contains(\"mini\"))    | not)
        | .id
    " | head -n 1)

    if test -n "$out_retry"
        yabai -m window $out_retry --space $target_space
    end
    if test -n "$zoom_retry"
        yabai -m window $zoom_retry --space $target_space
    end
    if test -n "$teams_retry"
        yabai -m window $teams_retry --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    # 在目标 space 内重新获取窗口 id
    set out (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Microsoft Outlook\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set zoom (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"zoom.us\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | select((.title | ascii_downcase | contains(\"meeting\")) | not)
        | select((.title | ascii_downcase | contains(\"video\"))   | not)
        | select((.title | ascii_downcase | contains(\"share\"))   | not)
        | select((.title | ascii_downcase | contains(\"screen\"))  | not)
        | select((.title | ascii_downcase | contains(\"mini\"))    | not)
        | .id
    " | head -n 1)

    set teams (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Microsoft Teams\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | select((.title | ascii_downcase | contains(\"meeting\")) | not)
        | select((.title | ascii_downcase | contains(\"video\"))   | not)
        | select((.title | ascii_downcase | contains(\"call\"))    | not)
        | select((.title | ascii_downcase | contains(\"share\"))   | not)
        | select((.title | ascii_downcase | contains(\"screen\"))  | not)
        | select((.title | ascii_downcase | contains(\"mini\"))    | not)
        | .id
    " | head -n 1)

    # 保持原来的布局：上半 Zoom 左、Teams 右；下半 Outlook 全宽
    if test -n "$zoom"
        yabai -m window $zoom --grid 2:2:0:0:1:1
    end
    if test -n "$teams"
        yabai -m window $teams --grid 2:2:1:0:1:1
    end
    if test -n "$out"
        yabai -m window $out --grid 2:1:0:1:1:1
    end

    focus_space_if_needed $target_space
end
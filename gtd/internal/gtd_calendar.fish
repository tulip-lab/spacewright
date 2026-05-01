function gtd_calendar
    set label gtd_calendar
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

    set calendar (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Calendar")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    set reminders (yabai -m query --windows | jq -r '
        .[]
        | select(.app=="Reminders")
        | select(.["is-minimized"]==false)
        | .id
    ' | head -n 1)

    if test -n "$calendar"
        yabai -m window $calendar --space $target_space
    end
    if test -n "$reminders"
        yabai -m window $reminders --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    set calendar_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Calendar\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set reminders_retry (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Reminders\")
        | select(.space!=$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    if test -n "$calendar_retry"
        yabai -m window $calendar_retry --space $target_space
    end
    if test -n "$reminders_retry"
        yabai -m window $reminders_retry --space $target_space
    end

    sleep 1
    focus_space_if_needed $target_space
    sleep 0.6

    set calendar (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Calendar\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    set reminders (yabai -m query --windows | jq -r "
        .[]
        | select(.app==\"Reminders\")
        | select(.space==$target_space)
        | select(.[\"is-minimized\"]==false)
        | .id
    " | head -n 1)

    # 左 Calendar，右 Reminders
    if test -n "$calendar"
        yabai -m window $calendar --grid 1:2:0:0:1:1
    end
    if test -n "$reminders"
        yabai -m window $reminders --grid 1:2:1:0:1:1
    end

    focus_space_if_needed $target_space
end
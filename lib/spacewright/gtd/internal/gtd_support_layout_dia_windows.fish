function gtd_support_layout_dia_windows --description "Apply GTD support Dia layouts for solo, wide, or tall mode"
    set -l mode $argv[1]
    set -e argv[1]

    set -l dia_windows $argv
    set -l dia_count (count $dia_windows)

    if test "$dia_count" -eq 0
        return 0
    end

    switch "$mode"
        case solo
            if test "$dia_count" -eq 1
                ws_window $dia_windows[1] --grid 1:1:0:0:1:1
            else if test "$dia_count" -eq 2
                ws_window $dia_windows[1] --grid 2:1:0:0:1:1
                ws_window $dia_windows[2] --grid 2:1:0:1:1:1
            else if test "$dia_count" -eq 3
                ws_window $dia_windows[1] --grid 2:2:0:0:1:1
                ws_window $dia_windows[2] --grid 2:2:1:0:1:1
                ws_window $dia_windows[3] --grid 2:1:0:1:1:1
            else
                set -l rows (math "ceil($dia_count / 2)")
                set -l i 1

                for wid in $dia_windows
                    set -l zero_index (math "$i - 1")
                    set -l col (math "$zero_index % 2")
                    set -l row (math "floor($zero_index / 2)")

                    ws_window $wid --grid $rows:2:$col:$row:1:1
                    set i (math "$i + 1")
                end
            end
        case wide
            set -l left_count (math "ceil($dia_count / 2)")
            set -l right_count (math "$dia_count - $left_count")
            set -l i 1

            while test "$i" -le "$left_count"
                ws_window $dia_windows[$i] --grid $left_count:2:0:(math "$i - 1"):1:1
                set i (math "$i + 1")
            end

            set i 1
            while test "$i" -le "$right_count"
                set -l window_index (math "$left_count + $i")

                ws_window $dia_windows[$window_index] --grid $right_count:2:1:(math "$i - 1"):1:1
                set i (math "$i + 1")
            end
        case tall
            if test "$dia_count" -eq 1
                ws_window $dia_windows[1] --grid 2:1:0:1:1:1
            else if test "$dia_count" -eq 2
                ws_window $dia_windows[1] --grid 2:1:0:0:1:1
                ws_window $dia_windows[2] --grid 2:1:0:1:1:1
            else if test "$dia_count" -eq 3
                ws_window $dia_windows[1] --grid 2:2:0:0:1:1
                ws_window $dia_windows[2] --grid 2:2:1:0:1:1
                ws_window $dia_windows[3] --grid 2:1:0:1:1:1
            else
                set -l rows (math "ceil($dia_count / 2)")
                set -l i 1

                for wid in $dia_windows
                    set -l zero_index (math "$i - 1")
                    set -l col (math "$zero_index % 2")
                    set -l row (math "floor($zero_index / 2)")

                    ws_window $wid --grid $rows:2:$col:$row:1:1
                    set i (math "$i + 1")
                end
            end
        case "*"
            echo "[WARN] gtd_support_layout_dia_windows expected mode must be one of: solo, wide, tall" >&2
            return 2
    end
end

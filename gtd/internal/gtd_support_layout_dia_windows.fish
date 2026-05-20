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
            if test "$dia_count" -eq 1
                ws_window $dia_windows[1] --grid 1:1:0:0:1:1
            else if test "$dia_count" -le 3
                set -l i 0

                for wid in $dia_windows
                    ws_window $wid --grid 1:$dia_count:$i:0:1:1
                    set i (math "$i + 1")
                end
            else
                set -l cols (math "ceil($dia_count / 2)")
                set -l i 1

                for wid in $dia_windows
                    set -l zero_index (math "$i - 1")
                    set -l col (math "$zero_index % $cols")
                    set -l row (math "floor($zero_index / $cols)")

                    ws_window $wid --grid 2:$cols:$col:$row:1:1
                    set i (math "$i + 1")
                end
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

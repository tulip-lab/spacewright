function gtd_support_layout_dia_windows --description "Apply GTD support Dia layouts for solo, wide, or tall mode"
    set -l mode $argv[1]
    set -e argv[1]
    argparse 'tall-bottom-grid=' -- $argv
    or return 2

    set -l dia_windows $argv
    set -l dia_count (count $dia_windows)

    if test "$dia_count" -eq 0
        return 0
    end

    switch "$mode"
        case solo
            if test "$dia_count" -eq 1
                ws_window $dia_windows[1] --grid 1:1:0:0:1:1
                or return 1
            else if test "$dia_count" -eq 2
                ws_window $dia_windows[1] --grid 2:1:0:0:1:1
                or return 1
                ws_window $dia_windows[2] --grid 2:1:0:1:1:1
                or return 1
            else if test "$dia_count" -eq 3
                ws_window $dia_windows[1] --grid 2:2:0:0:1:1
                or return 1
                ws_window $dia_windows[2] --grid 2:2:1:0:1:1
                or return 1
                ws_window $dia_windows[3] --grid 2:1:0:1:1:1
                or return 1
            else
                set -l rows (math "ceil($dia_count / 2)")
                set -l i 1

                for wid in $dia_windows
                    set -l zero_index (math "$i - 1")
                    set -l col (math "$zero_index % 2")
                    set -l row (math "floor($zero_index / 2)")

                    ws_window $wid --grid $rows:2:$col:$row:1:1
                    or return 1
                    set i (math "$i + 1")
                end
            end
        case wide
            set -l left_count (math "ceil($dia_count / 2)")
            set -l right_count (math "$dia_count - $left_count")
            set -l i 1

            while test "$i" -le "$left_count"
                ws_window $dia_windows[$i] --grid $left_count:2:0:(math "$i - 1"):1:1
                or return 1
                set i (math "$i + 1")
            end

            set i 1
            while test "$i" -le "$right_count"
                set -l window_index (math "$left_count + $i")

                ws_window $dia_windows[$window_index] --grid $right_count:2:1:(math "$i - 1"):1:1
                or return 1
                set i (math "$i + 1")
            end
        case tall
            set -l top_full_grid 2:1:0:0:1:1
            set -l bottom_full_grid 2:1:0:1:1:1
            set -l top_left_grid 2:2:0:0:1:1
            set -l top_right_grid 2:2:1:0:1:1
            set -l bottom_left_grid 2:2:0:1:1:1
            set -l bottom_right_grid 2:2:1:1:1:1
            if set -q _flag_tall_bottom_grid
                set -l parts (string split : -- "$_flag_tall_bottom_grid")
                if test (count $parts) -eq 6; and string match -qr '^[0-9]+$' -- $parts
                    set -l rows $parts[1]
                    set -l boundary $parts[4]
                    set -l bottom_height $parts[6]
                    if test "$rows" -gt 0; and test "$boundary" -gt 0; and test "$bottom_height" -gt 0
                        set top_full_grid "$rows:1:0:0:1:$boundary"
                        set bottom_full_grid "$rows:1:0:$boundary:1:$bottom_height"
                        set top_left_grid "$rows:2:0:0:1:$boundary"
                        set top_right_grid "$rows:2:1:0:1:$boundary"
                        set bottom_left_grid "$rows:2:0:$boundary:1:$bottom_height"
                        set bottom_right_grid "$rows:2:1:$boundary:1:$bottom_height"
                    end
                end
            end
            if test "$dia_count" -eq 1
                ws_window $dia_windows[1] --grid $bottom_full_grid
                or return 1
            else if test "$dia_count" -eq 2
                ws_window $dia_windows[1] --grid $top_full_grid
                or return 1
                ws_window $dia_windows[2] --grid $bottom_full_grid
                or return 1
            else if test "$dia_count" -eq 3
                ws_window $dia_windows[1] --grid $top_left_grid
                or return 1
                ws_window $dia_windows[2] --grid $top_right_grid
                or return 1
                ws_window $dia_windows[3] --grid $bottom_full_grid
                or return 1
            else if test "$dia_count" -eq 4
                ws_window $dia_windows[1] --grid $top_left_grid
                or return 1
                ws_window $dia_windows[2] --grid $top_right_grid
                or return 1
                ws_window $dia_windows[3] --grid $bottom_left_grid
                or return 1
                ws_window $dia_windows[4] --grid $bottom_right_grid
                or return 1
            else
                set -l rows (math "ceil($dia_count / 2)")
                set -l i 1

                for wid in $dia_windows
                    set -l zero_index (math "$i - 1")
                    set -l col (math "$zero_index % 2")
                    set -l row (math "floor($zero_index / 2)")

                    ws_window $wid --grid $rows:2:$col:$row:1:1
                    or return 1
                    set i (math "$i + 1")
                end
            end
        case "*"
            echo "[WARN] gtd_support_layout_dia_windows expected mode must be one of: solo, wide, tall" >&2
            return 2
    end
end

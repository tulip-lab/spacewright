function work_clear_bad_windows --description "Clear cached bad yabai window IDs"
    set -l bad_window_dir /tmp/workspace-ws-window-bad

    if test -d "$bad_window_dir"
        rm -rf "$bad_window_dir"
        echo "Cleared bad window cache: $bad_window_dir"
    else
        echo "Bad window cache is already empty"
    end
end

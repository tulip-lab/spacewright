function gtd_apply_support_space --description "Apply a GTD support workspace for Dia windows"
    argparse 'label=' 'display=' 'dia-layout=' dry-run -- $argv
    or return 1

    if not set -q _flag_label; or not set -q _flag_display; or not set -q _flag_dia_layout
        echo "usage: gtd_apply_support_space --label <label> --display <primary|wide|tall> --dia-layout <solo|wide|tall> [cleanup-spec ...]" >&2
        return 2
    end

    set -l cleanup_specs $argv
    if set -q _flag_dry_run
        printf "dry_run=gtd_apply_support_space\n"
        printf "label=%s\n" "$_flag_label"
        printf "display=%s\n" "$_flag_display"
        printf "apps=%s\n" (workspace_app_name dia)
        printf "dia_layout=%s\n" "$_flag_dia_layout"
        printf "cleanup=%s\n" "$cleanup_specs"
        return 0
    end

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    set -l windows_json (ws_query_windows $_flag_label initial); or return 1
    set -l dia_windows (printf '%s\n' "$windows_json" | gtd_support_find_dia_windows $_flag_label)
    or return 1

    if test (count $dia_windows) -eq 0
        destroy_empty_labeled_space $_flag_label
        return 0
    end

    set -l target_display (workspace_resolve_display_role $_flag_display)
    or return $status

    set -l target_space (workspace_prepare_labeled_space $_flag_label $target_display float $cleanup_specs)
    or return 1

    ws_move_windows_to_space $target_space $dia_windows

    set -l windows_json_final (ws_query_windows $_flag_label final); or return 1
    set dia_windows (printf '%s\n' "$windows_json_final" | ws_find_windows (workspace_app_name dia) --space $target_space)
    gtd_support_layout_dia_windows $_flag_dia_layout $dia_windows

    ws_focus_space $target_space

    workspace_run_cleanup_specs $cleanup_specs
    or return 1

    cleanup_unlabeled_empty_spaces $target_space
end

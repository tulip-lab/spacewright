function gtd_labels --description "Show all current GTD space labels"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Show all currently labeled GTD spaces.
    #
    # Notes:
    #   Only labels beginning with `gtd_` are included, so non-GTD labeled
    #   spaces from other workspace systems will not appear here.
    # -------------------------------------------------------------------------

    set -l spaces_json (ws_yabai -m query --spaces 2>/dev/null)
    if test $status -ne 0 -o -z "$spaces_json"
        echo "[WARN] gtd_labels could not query spaces from yabai" >&2
        return 1
    end

    echo $spaces_json | ws_jq '
        .[]
        | select(.label | test("^gtd_"))
        | {
            index,
            label,
            display
        }'
end

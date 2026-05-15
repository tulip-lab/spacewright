function gtd_reset_labels --description "Remove labels from all current GTD workspaces"
    # -------------------------------------------------------------------------
    # Purpose:
    #   Remove labels from all GTD workspaces currently used by the rebuilt GTD
    #   workspace system.
    #
    # Notes:
    #   This function only removes labels. It does not destroy spaces.
    #
    # Current GTD labels:
    #   - gtd_chat
    #   - gtd_calendar
    #   - gtd_mail_solo
    #   - gtd_mail_tall
    #   - gtd_mail_wide
    #   - gtd_meeting_solo
    #   - gtd_meeting_tall
    #   - gtd_meeting_wide
    #   - gtd_support_solo
    #   - gtd_support_tall
    #   - gtd_support_wide
    #   - gtd_review_solo
    #   - gtd_review_tall
    #   - gtd_review_wide
    # -------------------------------------------------------------------------

    set -l labels \
        gtd_chat \
        gtd_calendar \
        gtd_mail_solo \
        gtd_mail_tall \
        gtd_mail_wide \
        gtd_meeting_solo \
        gtd_meeting_tall \
        gtd_meeting_wide \
        gtd_support_solo \
        gtd_support_tall \
        gtd_support_wide \
        gtd_review_solo \
        gtd_review_tall \
        gtd_review_wide

    for label in $labels
        set -l spaces_json (ws_yabai -m query --spaces 2>/dev/null)
        if test $status -ne 0 -o -z "$spaces_json"
            echo "[WARN] gtd_reset_labels could not query spaces from yabai" >&2
            return 1
        end

        set -l spaces (echo $spaces_json | jq -r --arg label "$label" '.[] | select(.label==$label) | .index')
        for s in $spaces
            ws_yabai -m space $s --label "" >/dev/null 2>&1
        end
    end
end

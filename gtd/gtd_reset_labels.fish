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
    #   - gtd_mail_tall
    #   - gtd_mail_wide
    #   - gtd_meeting_tall
    #   - gtd_meeting_wide
    #   - gtd_support_tall
    #   - gtd_support_wide
    #   - gtd_review_tall
    #   - gtd_review_wide
    # -------------------------------------------------------------------------

    set -l labels \
        gtd_chat \
        gtd_calendar \
        gtd_mail_tall \
        gtd_mail_wide \
        gtd_meeting_tall \
        gtd_meeting_wide \
        gtd_support_tall \
        gtd_support_wide \
        gtd_review_tall \
        gtd_review_wide

    for label in $labels
        set -l spaces (yabai -m query --spaces | jq -r --arg label "$label" '.[] | select(.label==$label) | .index')
        for s in $spaces
            yabai -m space $s --label ""
        end
    end
end
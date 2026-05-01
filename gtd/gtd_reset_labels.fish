function gtd_reset_labels
    set labels \
        gtd_mail_wide \
        gtd_meeting_wide \
        gtd_support_wide \
        gtd_chat \
        gtd_mail_thunderbird \
        gtd_mail_outlook \
        gtd_calendar_reminder \
        gtd_meeting

    for label in $labels
        set spaces (yabai -m query --spaces | jq -r ".[] | select(.label==\"$label\") | .index")
        for s in $spaces
            yabai -m space $s --label ""
        end
    end
end
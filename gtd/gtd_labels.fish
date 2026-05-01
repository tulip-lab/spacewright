function gtd_labels
    yabai -m query --spaces | jq '.[] | select(.label!="") | {index, label, display}'
end
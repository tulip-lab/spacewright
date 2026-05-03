function resolve_target_display --description "Resolve target display index from UUID with fallback"
    set -l target_uuid $argv[1]
    set -l fallback_display $argv[2]

    if test -z "$fallback_display"
        set fallback_display 1
    end

    if test -z "$target_uuid"
        echo $fallback_display
        return 0
    end

    set -l displays_json (yabai -m query --displays 2>/dev/null)
    if test -z "$displays_json"
        echo $fallback_display
        return 0
    end

    set -l target_display (echo $displays_json | jq -r --arg uuid "$target_uuid" '.[] | select(.uuid==$uuid) | .index' | head -n 1)

    if test -z "$target_display"
        echo $fallback_display
    else
        echo $target_display
    end
end
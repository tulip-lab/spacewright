function workspace_app_names --description "Print known yabai app names for a workspace app key"
    set -l key $argv[1]

    switch "$key"
        case code
            printf "%s\n" Code
        case claude
            printf "%s\n" Claude
        case chatgpt
            printf "%s\n" ChatGPT
        case obsidian
            printf "%s\n" Obsidian
        case zotero
            printf "%s\n" Zotero
        case thunderbird
            printf "%s\n" Thunderbird thunderbird
        case word
            printf "%s\n" "Microsoft Word"
        case powerpoint
            printf "%s\n" "Microsoft PowerPoint"
        case outlook
            printf "%s\n" "Microsoft Outlook"
        case zoom
            printf "%s\n" "zoom.us" Zoom
        case teams
            printf "%s\n" "Microsoft Teams" MSTeams
        case dia
            printf "%s\n" Dia
        case finder
            printf "%s\n" Finder
        case preview
            printf "%s\n" Preview 预览
        case notes
            printf "%s\n" Notes
        case calendar
            printf "%s\n" Calendar
        case reminders
            printf "%s\n" Reminders
        case wechat
            printf "%s\n" WeChat
        case keybase
            printf "%s\n" Keybase
        case messages
            printf "%s\n" Messages
        case dingtalk
            printf "%s\n" DingTalk 钉钉
        case whatsapp
            printf "%s\n" WhatsApp
        case warp
            printf "%s\n" Warp
        case smartgit
            printf "%s\n" SmartGit
        case keepassx
            printf "%s\n" KeePassXC KeePassX
        case flclash
            printf "%s\n" FlClash
        case thaw
            printf "%s\n" Thaw
        case '*'
            echo "[WARN] workspace_app_names: unknown app key: $key" >&2
            return 2
    end
end

function workspace_app_name --description "Print the primary yabai app name for a workspace app key"
    set -l names (workspace_app_names $argv[1])
    or return 1

    if test (count $names) -eq 0
        return 1
    end

    echo $names[1]
end

function workspace_app_names_json --description "Print a JSON array of known yabai app names for workspace app keys"
    set -l names

    for key in $argv
        set -l key_names (workspace_app_names $key)
        or return 1

        set -a names $key_names
    end

    printf "%s\n" $names | ws_jq -R . | ws_jq -s .
end

function workspace_app_regex --description "Print an anchored regex for one or more workspace app keys"
    set -l escaped_names

    for key in $argv
        set -l key_names (workspace_app_names $key)
        or return 1

        for app_name in $key_names
            set -a escaped_names (string escape --style=regex -- $app_name)
        end
    end

    if test (count $escaped_names) -eq 0
        return 1
    end

    printf "^(%s)\$\\n" (string join '|' $escaped_names)
end

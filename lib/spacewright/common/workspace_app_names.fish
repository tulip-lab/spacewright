function workspace_app_names --description "Print known yabai app names for a workspace app key"
    set -l key $argv[1]

    if test -z "$key"
        echo "usage: workspace_app_names <app-key>" >&2
        return 2
    end

    set -l names (spacewright_config_effective | jq -r --arg key "$key" '.apps[$key].names[]? // empty')
    if test $status -ne 0; or test (count $names) -eq 0
        echo "[WARN] workspace_app_names: unknown app key: $key" >&2
        return 2
    end

    printf "%s\n" $names
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

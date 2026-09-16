function spacewright_config_default_file --description "Print the package default configuration path"
    echo "$SPACEWRIGHT_PACKAGE_ROOT/config/defaults.json"
end

function spacewright_config_user_file --description "Print the user configuration path"
    if set -q SPACEWRIGHT_CONFIG_FILE; and test -n "$SPACEWRIGHT_CONFIG_FILE"
        echo "$SPACEWRIGHT_CONFIG_FILE"
    else
        echo "$SPACEWRIGHT_CONFIG_ROOT/config.json"
    end
end

function spacewright_config_effective --description "Merge package defaults with an optional user configuration"
    set -l default_file (spacewright_config_default_file)
    set -l user_file (spacewright_config_user_file)

    if not test -r "$default_file"
        echo "[WARN] SpaceWright default config is not readable: $default_file" >&2
        return 1
    end

    if test -e "$user_file"; and not test -r "$user_file"
        echo "[WARN] SpaceWright user config is not readable: $user_file" >&2
        return 1
    end

    if test -r "$user_file"
        jq -s 'reduce .[] as $item ({}; . * $item)' "$default_file" "$user_file"
    else
        jq . "$default_file"
    end
end

function workspace_config_check --description "Validate the effective SpaceWright v1 configuration"
    set -l config (spacewright_config_effective | string collect)
    or return 1

    printf "%s\n" "$config" | jq -e '
        def nonempty_strings:
            type == "array" and length > 0 and all(.[]; type == "string" and length > 0);
        def valid_action:
            type == "object"
            and (.role | type == "string" and length > 0)
            and ([has("grid"), has("move_abs"), has("resize_abs")] | any);
        def valid_window($apps):
            type == "object"
            and (.role | type == "string" and length > 0)
            and (.app_key | type == "string" and $apps[.] != null)
            and (.required | type == "boolean");

        .version == 1
        and (.apps | type == "object" and length > 0)
        and ([.apps[] | (.names | nonempty_strings)] | all)
        and (.layouts | type == "object" and length > 0)
        and ([.layouts[] | type == "array" and length > 0 and all(.[]; valid_action)] | all)
        and (.workspaces | type == "object")
        and (. as $root | [.workspaces[] |
            (.label | type == "string" and length > 0)
            and (.runner | IN("primary_helper", "office_document", "gtd_support", "gtd_review", "gtd_meeting", "gtd_ai", "fixed_adapter"))
            and (.display_role | IN("primary", "external", "solo", "wide", "tall", "auto_external"))
            and (.space_layout | IN("float", "bsp", "stack"))
            and (.windows | type == "array" and length > 0 and all(.[]; valid_window($root.apps)))
            and (.layout_ref | type == "string" and $root.layouts[.] != null)
            and ((.primary_alone_layout_ref // null) as $ref | $ref == null or $root.layouts[$ref] != null)
            and (
                if (.runner | IN("office_document", "gtd_support")) then
                    (.runner_options.mode | IN("solo", "wide", "tall"))
                elif .runner == "fixed_adapter" then
                    (.runner_options.adapter | IN("coding_control", "gtd_chat", "gtd_calendar"))
                else true
                end
            )
        ] | all)
        and (. as $root | [.modes[]? |
            type == "object"
            and (.display_mode | IN("solo", "wide", "tall", "auto"))
            and (.steps | type == "array" and length > 0)
            and (all(.steps[];
                (has("workspace") and ($root.workspaces[.workspace] != null))
                or (has("mode") and ($root.modes[.mode] != null) and (.mode | IN("coding_solo", "gtd_solo_all", "office_wide", "office_tall")))
                or (has("postprocessor") and (.postprocessor | IN("gtd_ai_expand_hermes_when_alone", "workspace_reconcile_primary_fixed_spaces")))
            ))
            and ((.cleanup // []) | type == "array" and all(.[]; type == "string" and test("^[a-z_]+:(solo|wide|tall)$")))
        ] | all)
    ' >/dev/null
    or begin
        echo "[WARN] SpaceWright configuration failed v1 validation" >&2
        return 1
    end

    return 0
end

function workspace_config_get --description "Print one configured workspace as JSON"
    set -l workspace_id $argv[1]
    if test -z "$workspace_id"
        echo "usage: workspace_config_get <workspace>" >&2
        return 2
    end

    workspace_config_check
    or return 1

    spacewright_config_effective | jq -e --arg id "$workspace_id" '.workspaces[$id] // error("unknown workspace: " + $id)'
end

function workspace_config_plan --description "Print a read-only configured workspace or mode plan"
    set -l target $argv[1]
    if test -z "$target"
        echo "usage: workspace_config_plan <workspace-or-mode>" >&2
        return 2
    end

    workspace_config_check
    or return 1

    spacewright_config_effective | jq -e --arg target "$target" '
        if .workspaces[$target] != null then
            {
                kind: "workspace",
                id: $target,
                runner: .workspaces[$target].runner,
                label: .workspaces[$target].label,
                display_role: .workspaces[$target].display_role,
                space_layout: .workspaces[$target].space_layout,
                windows: [.workspaces[$target].windows[] as $window | $window + {app_names: .apps[$window.app_key].names}],
                layout: .layouts[.workspaces[$target].layout_ref],
                primary_alone_layout: (.workspaces[$target].primary_alone_layout_ref as $ref | if $ref then .layouts[$ref] else null end),
                runner_options: (.workspaces[$target].runner_options // {}),
                cleanup: (.workspaces[$target].cleanup // null),
                mutates: false
            }
        elif .modes[$target] != null then
            {
                kind: "mode",
                id: $target,
                display_mode: .modes[$target].display_mode,
                steps: .modes[$target].steps,
                cleanup: (.modes[$target].cleanup // []),
                mutates: false
            }
        else
            error("unknown workspace or mode: " + $target)
        end
    '
end

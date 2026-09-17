function workspace_verify_primary_fixed_separation --description "Verify distinct ownership for GTD chat and coding control Spaces"
    set -l primary_display (resolve_workspace_primary_display)
    or return 1
    if test -z "$primary_display"
        return 1
    end

    set -l spaces_json (ws_query_spaces workspace_verify_primary_fixed_separation spaces)
    or return 1
    set -l windows_json (ws_query_windows workspace_verify_primary_fixed_separation windows)
    or return 1

    set -l chat_apps_json (workspace_app_names_json wechat keybase dingtalk messages whatsapp facetime)
    or return 1
    set -l control_apps_json (workspace_app_names_json warp smartgit keepassx flclash thaw portfolio_performance)
    or return 1

    printf '%s\n' "$spaces_json" | ws_jq -e \
        --argjson windows "$windows_json" \
        --argjson chat_apps "$chat_apps_json" \
        --argjson control_apps "$control_apps_json" \
        --argjson primary_display "$primary_display" '
            def labeled($name): [.[] | select(.label == $name)];
            def owned($spaces; $apps):
                all($windows[]; . as $window
                    | (($window["is-sticky"] // false) == true)
                    or (([$spaces[].index] | index($window.space)) == null)
                    or ($apps | index($window.app) != null));
            def app_windows($apps):
                [$windows[]
                    | . as $window
                    | select(($apps | index($window.app)) != null)
                    | select((.["is-minimized"] // false) != true)
                    | select((.["is-sticky"] // false) != true)];
            def assigned($spaces; $owned_windows):
                if ($owned_windows | length) == 0 then true
                else ($spaces | length) == 1
                    and all($owned_windows[]; .space == $spaces[0].index)
                end;
            (labeled("gtd_chat")) as $chat
            | (labeled("coding_control")) as $control
            | app_windows($chat_apps) as $chat_windows
            | app_windows($control_apps) as $control_windows
            | ($chat | length) <= 1
            and ($control | length) <= 1
            and all(($chat + $control)[]; .display == $primary_display)
            and (($chat | length) == 0 or ($control | length) == 0 or $chat[0].uuid != $control[0].uuid)
            and assigned($chat; $chat_windows)
            and assigned($control; $control_windows)
            and owned($chat; $chat_apps)
            and owned($control; $control_apps)
        ' >/dev/null
end

function workspace_reconcile_primary_fixed_spaces --description "Verify and reconcile GTD chat and coding control separation once"
    if workspace_verify_primary_fixed_separation
        return 0
    end

    echo "[WARN] primary fixed Spaces are mixed; reconciling coding_control then gtd_chat" >&2
    set -l failed 0

    # coding_control may preserve an app-owned SmartGit Space by moving the
    # whole Space across displays. Run it first because that operation can
    # renumber primary-display Spaces; gtd_chat then restores its final label
    # and ownership against the settled indices.
    coding_control
    or set failed 1

    gtd_chat
    or set failed 1

    workspace_verify_primary_fixed_separation
    or set failed 1

    return $failed
end

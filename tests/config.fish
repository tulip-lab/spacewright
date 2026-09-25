#!/usr/bin/env fish

set -l test_file (path resolve (status filename))
set -l package_root (path dirname (path dirname $test_file))
set -l test_root (mktemp -d /private/tmp/spacewright-config-test.XXXXXX)

set -gx SPACEWRIGHT_PACKAGE_ROOT "$package_root"
set -gx SPACEWRIGHT_ROOT "$package_root/lib/spacewright"
set -gx SPACEWRIGHT_CONFIG_ROOT "$test_root/config"
mkdir -p "$SPACEWRIGHT_CONFIG_ROOT"
source "$package_root/conf.d/spacewright.fish"

workspace_config_check
or exit 1

set -l plan (workspace_config_plan coding_editor_wide | string collect)
or exit 2
printf "%s\n" "$plan" | jq -e '
    .kind == "workspace"
    and .mutates == false
    and .display_role == "wide"
    and (.windows | length) == 2
' >/dev/null
or exit 3

set -l configured_dry_run (workspace_run_configured coding_editor_wide --dry-run | string collect)
or exit 4
set -l legacy_dry_run (__coding_editor_wide_legacy_body --dry-run | string collect)
or exit 5
test "$configured_dry_run" = "$legacy_dry_run"
or exit 6

set -l expected_workspaces \
    coding_control coding_editor_solo coding_editor_tall coding_editor_wide \
    gtd_ai_solo gtd_ai_tall gtd_ai_wide gtd_calendar gtd_chat \
    gtd_mail_solo gtd_mail_tall gtd_mail_wide \
    gtd_meeting_solo gtd_meeting_tall gtd_meeting_wide \
    gtd_review_solo gtd_review_tall gtd_review_wide \
    gtd_support_solo gtd_support_tall gtd_support_wide \
    office_slides_tall office_slides_wide office_writing_tall office_writing_wide \
    research_solo research_tall research_wide
set -l actual_workspaces (spacewright_config_effective | jq -r '.workspaces | keys[]')
test (string join ' ' -- $actual_workspaces) = (string join ' ' -- $expected_workspaces)
or exit 20

set -l expected_modes coding_solo coding_tall coding_wide gtd_solo_all gtd_tall gtd_wide office_tall office_wide work_solo work_tall work_wide
set -l actual_modes (spacewright_config_effective | jq -r '.modes | keys[]')
test (string join ' ' -- $actual_modes) = (string join ' ' -- $expected_modes)
or exit 21

spacewright_config_effective | jq -e '
    .modes.work_solo.cleanup == [
        "coding:wide", "coding:tall", "research:wide", "research:tall",
        "office:wide", "office:tall", "gtd:wide", "gtd:tall"
    ]
    and .modes.work_wide.cleanup == [
        "coding:tall", "coding:solo", "research:tall", "research:solo",
        "office:tall", "gtd:tall", "gtd:solo"
    ]
    and .modes.work_tall.cleanup == [
        "coding:wide", "coding:solo", "research:wide", "research:solo",
        "office:wide", "gtd:wide", "gtd:solo"
    ]
' >/dev/null
or exit 30

set -l workspace_body_rows \
    coding_editor_solo:__coding_editor_solo_body \
    coding_editor_wide:__coding_editor_wide_legacy_body \
    coding_editor_tall:__coding_editor_tall_body \
    research_solo:__research_solo_body \
    research_wide:__research_wide_body \
    research_tall:__research_tall_body \
    office_writing_wide:__office_writing_wide_body \
    office_slides_wide:__office_slides_wide_body \
    office_writing_tall:__office_writing_tall_body \
    office_slides_tall:__office_slides_tall_body \
    gtd_support_solo:__gtd_support_solo_body \
    gtd_support_wide:__gtd_support_wide_body \
    gtd_support_tall:__gtd_support_tall_body \
    gtd_review_solo:__gtd_review_solo_body \
    gtd_review_wide:__gtd_review_wide_body \
    gtd_review_tall:__gtd_review_tall_body \
    gtd_mail_solo:__gtd_mail_solo_body \
    gtd_mail_wide:__gtd_mail_wide_body \
    gtd_mail_tall:__gtd_mail_tall_body \
    gtd_meeting_solo:__gtd_meeting_solo_body \
    gtd_meeting_wide:__gtd_meeting_wide_body \
    gtd_meeting_tall:__gtd_meeting_tall_body \
    gtd_ai_solo:__gtd_ai_solo_body \
    gtd_ai_wide:__gtd_ai_wide_body \
    gtd_ai_tall:__gtd_ai_tall_body \
    coding_control:__coding_control_body \
    gtd_chat:__gtd_chat_body \
    gtd_calendar:__gtd_calendar_body

for row in $workspace_body_rows
    set -l parts (string split -m1 ':' -- "$row")
    set -l workspace_id $parts[1]
    set -l legacy_body $parts[2]
    set -l configured_output (workspace_run_configured $workspace_id --dry-run | string collect)
    or exit 22
    set -lx SPACEWRIGHT_CONFIG_DISABLE 1
    set -l legacy_output ($legacy_body --dry-run | string collect)
    or exit 23
    if test "$configured_output" != "$legacy_output"
        echo "configured dry-run drift: $workspace_id" >&2
        exit 24
    end

    set -l observation_spec (workspace_observation_spec $workspace_id | string collect)
    or exit 28
    printf "%s\n" "$observation_spec" | jq -e --arg id "$workspace_id" '
        .workspace == $id
        and (.label | type == "string" and length > 0)
        and (.roles | type == "array" and length > 0)
        and all(.roles[]; (.app_names | length) > 0 and (.layout.kind | IN("none", "grid", "region", "absolute")))
    ' >/dev/null
    or exit 29
end

for mode_id in $expected_modes
    set -l configured_output (workspace_run_configured_mode $mode_id --dry-run | string collect)
    or exit 25
    set -l legacy_body __$mode_id"_body"
    set -lx SPACEWRIGHT_CONFIG_DISABLE 1
    set -l legacy_output ($legacy_body --dry-run | string collect)
    or exit 26
    if test "$configured_output" != "$legacy_output"
        echo "configured mode dry-run drift: $mode_id" >&2
        exit 27
    end
end

set -g __spacewright_config_apply_calls 0
function workspace_find_app_key_window
    echo 42
end
function workspace_apply_primary_helper_space
    set -g __spacewright_config_apply_calls (math $__spacewright_config_apply_calls + 1)
end
workspace_run_configured coding_editor_wide
or exit 7
test $__spacewright_config_apply_calls -eq 1
or exit 8

function workspace_find_app_key_window
    return 2
end
set -g __spacewright_config_apply_calls 0
if workspace_run_configured coding_editor_wide >/dev/null 2>&1
    exit 9
end
test $__spacewright_config_apply_calls -eq 0
or exit 10

printf '%s\n' '{"version":1,"apps":{"code":{"names":["Custom Code"]}}}' > "$SPACEWRIGHT_CONFIG_ROOT/config.json"
workspace_config_check
or exit 11

set -l configured_names (spacewright_config_effective | jq -r '.apps.code.names[]')
test "$configured_names" = "Custom Code"
or exit 12
test (workspace_app_name code) = "Custom Code"
or exit 13

printf '%s\n' '{
  "version": 1,
  "modes": {
    "work_wide": {
      "display_mode": "wide",
      "steps": [
        {"workspace":"gtd_calendar"},
        {"workspace":"coding_control"},
        {"workspace":"gtd_chat"}
      ]
    }
  }
}' > "$SPACEWRIGHT_CONFIG_ROOT/config.json"
set -l configured_order (workspace_order_mode_spaces --dry-run wide | string collect)
string match -q '*primary=gtd_calendar,coding_control,gtd_chat*' -- "$configured_order"
or exit 31

printf '%s\n' '{"version":2}' > "$SPACEWRIGHT_CONFIG_ROOT/config.json"
if workspace_config_check >/dev/null 2>&1
    exit 14
end

echo "OK      config validation, override, runtime parity, and fail-closed preflight"

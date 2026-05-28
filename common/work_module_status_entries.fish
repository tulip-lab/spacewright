function workspace_simple_module_status --description "Print a standard module status snapshot and app list"
    set -l caller $argv[1]
    set -l title $argv[2]
    set -l app_keys $argv[3..-1]

    if test -z "$caller" -o -z "$title" -o (count $app_keys) -eq 0
        echo "usage: workspace_simple_module_status <caller> <title> <app-key>..." >&2
        return 2
    end

    if test "$WORKSPACE_SKIP_STATUS_SNAPSHOT" != "1"
        workspace_status_snapshot
    end

    workspace_print_app_status --title "$title" --caller "$caller" $app_keys
end

function coding_status --description "Show display, space and coding application status"
    workspace_simple_module_status coding_status "CODING APPS" code codex warp smartgit flclash thaw
end

function office_status --description "Show display, space and office application status"
    workspace_simple_module_status office_status "OFFICE APPS" word powerpoint chatgpt
end

function research_status --description "Show display, space and research application status"
    workspace_simple_module_status research_status "RESEARCH APPS" zotero chatgpt
end

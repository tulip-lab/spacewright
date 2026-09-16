# Repository Boundary And Source Inventory

## Purpose

This document assigns every current workspace source area to an import and
final ownership category. It is the Phase 0 authority for the upcoming
history-preserving import.

## Ownership Categories

- **Engine**: portable implementation owned by SpaceWright.
- **Consumer config**: personal declarative facts owned by Mackup.
- **Split**: the current file combines engine and personal facts; import it as
  legacy, then separate it behind tests.
- **Integration**: optional adapter or example; the user's live version stays
  in Mackup.
- **Machine state**: never versioned as portable source.
- **Legacy documentation**: imported for history and behavioral evidence, then
  superseded by product or consumer documentation as appropriate.

## Import Rule

Phase 1 imports the complete tracked subtree
`.config/fish/functions/workspace/` into an isolated legacy/source boundary in
SpaceWright. This preserves ancestry and provides an exact behavioral baseline.
The classification below controls the final refactor; it is not permission to
omit files from the baseline import.

## Workspace Subtree Inventory

Paths in this table are relative to
`.config/fish/functions/workspace/` in the Mackup source repository.

| Current path | Initial import | Final ownership | Notes |
|---|---|---|---|
| `README.md` | Complete | Split | Product command docs move to SpaceWright; personal workflows remain consumer docs. |
| `design-notes.md` | Complete | Legacy documentation | Preserve decisions; rewrite portable architecture here and consumer behavior in Mackup. |
| `common/ws_core.fish` | Complete | Engine | Bounded yabai/jq queries and recovery. |
| `common/ws_find_windows.fish` | Complete | Engine | Structured window selection mechanics. |
| `common/ws_move_windows_to_space.fish` | Complete | Engine | Movement and confirmation mechanics. |
| `common/ws_window.fish` | Complete | Engine | Window layout primitive. |
| `common/workspace_app_bounds.fish` | Complete | Engine | Bounded app-bounds fallback. |
| `common/workspace_app_space_fallback.fish` | Complete | Engine | Fallback mechanics, not app policy. |
| `common/workspace_app_window_lifecycle.fish` | Complete | Engine | Capture/refresh lifecycle. |
| `common/workspace_app_window_selectors.fish` | Complete | Engine | Selector implementation. |
| `common/workspace_apply_primary_helper_space.fish` | Complete | Engine | Generic primary/helper runner. |
| `common/workspace_cleanup_spaces.fish` | Complete | Engine | Safe cleanup mechanics. |
| `common/workspace_display_roles.fish` | Complete | Split | Resolver is engine; UUID value and role preferences are state/config. |
| `common/workspace_finalize.fish` | Complete | Engine | Finalization transaction. |
| `common/workspace_label_recovery.fish` | Complete | Engine | Explicit label recovery. |
| `common/workspace_labeled_space_focus.fish` | Complete | Engine | Space focus mechanics. |
| `common/workspace_labeled_space_lifecycle.fish` | Complete | Engine | Label creation/reuse mechanics. |
| `common/workspace_observability.fish` | Complete | Split | Snapshot/plan/verify engine stays; observed workspace declarations become config. |
| `common/workspace_primary_fixed_separation.fish` | Complete | Split | Verification/reconciliation is engine; fixed labels and ownership are config. |
| `common/workspace_retarget_contaminated_space.fish` | Complete | Engine | Generic safe retargeting. |
| `common/workspace_runners.fish` | Complete | Engine | Step, cleanup, and mode runner mechanics. |
| `common/workspace_sandbox.fish` | Complete | Split | Collection mechanics are engine; managed-app boundary and labels are config. |
| `common/workspace_space_fallback.fish` | Complete | Engine | Generic fallback Space mechanics. |
| `common/workspace_status_helpers.fish` | Complete | Engine | Status presentation mechanics. |
| `common/workspace_app_names.fish` | Complete | Consumer config | App aliases move to user configuration; SpaceWright ships schema/examples. |
| `common/workspace_manifest.fish` | Complete | Split | Product capabilities remain code; workspace/app/mode declarations move to config. |
| `common/workspace_ownership_policy.fish` | Complete | Consumer config | Ownership facts become validated workspace/window-role configuration. |
| `common/workspace_order_spaces.fish` | Complete | Split | Ordering algorithm is engine; ordered label lists are config. |
| `common/work_entries.fish` | Complete | Consumer config | Mode composition becomes configuration behind stable wrappers. |
| `common/source_workspace_common.fish` | Complete | Engine | Replace fixed source paths with the package loader. |
| `common/workspace_module_reloads.fish` | Complete | Split | Loader mechanics are engine; enabled module list is config. |
| `common/work_reload.fish` | Complete | Engine | Becomes relocatable package reload/bootstrap. |
| `common/work_audit.fish` | Complete | Engine | Architecture/config audit. |
| `common/work_bad_windows.fish` | Complete | Engine | Diagnostics over machine-local cache. |
| `common/work_clear_bad_windows.fish` | Complete | Engine | Explicit cache maintenance; cache itself is state. |
| `common/work_command_check.fish` | Complete | Engine | Installed command validation. |
| `common/work_diagnostics.fish` | Complete | Engine | Read-only diagnostics. |
| `common/work_display_health.fish` | Complete | Split | Health mechanics are engine; expected profile geometry is integration/config. |
| `common/work_doctor.fish` | Complete | Engine | Must resolve package/config/state roots. |
| `common/work_inventory.fish` | Complete | Engine | Reports effective package and configuration inventory. |
| `common/work_smoke.fish` | Complete | Engine | Read-only regression entry. |
| `common/work_smoke_finalization.fish` | Complete | Engine test | Convert embedded fixtures into SpaceWright tests. |
| `common/work_smoke_observability.fish` | Complete | Engine test | Convert embedded fixtures into SpaceWright tests. |
| `common/yabai_doctor.fish` | Complete | Engine | Read-only by default; explicit repair remains separately authorized. |
| `display/display_entries.fish` | Complete | Integration | Keep command interface; inject consumer-owned display profile commands. |
| `coding/coding_entries.fish` | Complete | Consumer config | Labels, apps, grids, and mode composition become user configuration. |
| `coding/internal/coding_control.fish` | Complete | Split | Generic multi-window/layout mechanics may move to engine; current apps and geometry remain consumer config. |
| `research/research_entries.fish` | Complete | Consumer config | Workspace definition and layouts become user configuration. |
| `office/office_entries.fish` | Complete | Split | Adaptive multi-document runner is engine; Word/PowerPoint/ChatGPT definitions and layouts are config. |
| `gtd/gtd_entries.fish` | Complete | Consumer config | Workspace definitions, labels, modes, and layouts remain personal config. |
| `gtd/gtd_apps.fish` | Complete | Consumer integration | App inventory derives from effective config rather than a fixed GTD list. |
| `gtd/gtd_status.fish` | Complete | Split | Generic status stays; GTD naming and app set are config. |
| `gtd/internal/gtd_apply_ai_space.fish` | Complete | Split | Reusable runner/recovery may become engine adapter; apps/layout stay config. |
| `gtd/internal/gtd_apply_meeting_space.fish` | Complete | Split | Meeting recovery can be an optional engine adapter; apps/layout stay config. |
| `gtd/internal/gtd_apply_review_space.fish` | Complete | Split | Multi-window/fallback mechanics may be engine; workflow facts stay config. |
| `gtd/internal/gtd_apply_support_space.fish` | Complete | Split | Dia mechanics may be an adapter; workflow facts stay config. |
| `gtd/internal/gtd_calendar.fish` | Complete | Consumer extension | Personal Calendar/Reminders workspace stays consumer-side until generalized. |
| `gtd/internal/gtd_chat.fish` | Complete | Consumer extension | Personal chat-app ownership stays consumer-side until generalized. |
| `gtd/internal/gtd_find_meeting_window.fish` | Complete | Engine adapter | Optional Zoom/Teams window recovery adapter. |
| `gtd/internal/gtd_find_outlook_window.fish` | Complete | Engine adapter | Optional Outlook selector/recovery adapter. |
| `gtd/internal/gtd_reopen_outlook.fish` | Complete | Engine adapter | Explicit bounded Outlook recovery. |
| `gtd/internal/gtd_support_find_dia_windows.fish` | Complete | Engine adapter | Optional Dia selector adapter. |
| `gtd/internal/gtd_support_layout_dia_windows.fish` | Complete | Split | Layout algorithm may be adapter; geometry/preferences become config. |

The path rows above cover every tracked file currently under
`.config/fish/functions/workspace/`: the two Markdown files, all common files,
the display entry, and every coding, research, office, and GTD file.

## Adjacent Integration Inventory

These files are not part of the core history split:

| Mackup path | Ownership | SpaceWright treatment |
|---|---|---|
| `.config/displayprofiles/display-solo-primary.fish` | Consumer integration | Document adapter contract; ship a sanitized example only. |
| `.config/displayprofiles/display-primary-plus-wide-left.fish` | Consumer integration | Document adapter contract; ship a sanitized example only. |
| `.config/displayprofiles/display-primary-plus-tall-left.fish` | Consumer integration | Document adapter contract; ship a sanitized example only. |
| `.config/displayprofiles/display-external-wide-left-tall-right.fish` | Consumer integration | Historical/alternative consumer profile; do not import into core. |
| `.config/displayprofiles/design-notes.md` | Consumer documentation | Summarize portable interface requirements in SpaceWright docs. |
| `.config/skhd/skhdrc` | Consumer integration | Keep live bindings in Mackup; ship optional examples. |
| `.config/skhd/README.md` | Consumer documentation | Keep shortcut table with the live config. |
| `.config/skhd/design-notes.md` | Consumer documentation | Keep personal binding rationale in Mackup. |
| `.config/yabai/yabairc` | Consumer integration | Keep live yabai configuration in Mackup; document prerequisites. |
| `.config/yabai/design-notes.md` | Consumer documentation | Summarize only portable prerequisites in SpaceWright. |

## Machine-Local State

The following never belongs in portable Git history:

- workspace primary display UUID;
- yabai display, Space, and window snapshots;
- bad-window cache entries;
- restart timestamps/generations and finalization depth;
- installation-specific absolute roots;
- logs, temporary fixtures generated during live runs, or credentials.

Machine state will eventually live below a dedicated state root. Mackup may
store reviewed portable configuration but must not version runtime state.

## Configuration Hand-off

Mackup will eventually expose user configuration at SpaceWright's documented
configuration root, typically through its normal symlink/projection mechanism.
The package consumes only the effective configuration file; it does not know
that Mackup is the source repository.

Mackup will pin a SpaceWright release or immutable commit. It will not track an
unversioned development branch for daily runtime use.

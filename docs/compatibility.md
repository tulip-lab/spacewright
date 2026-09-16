# Compatibility Contract

## Scope

The migration must preserve the current user-facing command surface while the
implementation moves from Mackup to SpaceWright. Internal helper names may
change after equivalent tests exist.

## Stable Public Commands

The initial compatibility set includes these command families:

- top-level modes: `work_solo`, `work_wide`, `work_tall`;
- coding: `coding_solo`, `coding_wide`, `coding_tall`,
  `coding_editor_*`, and `coding_control`;
- research: `research_solo`, `research_wide`, `research_tall`;
- office: `office_wide`, `office_tall`, `office_writing_*`, and
  `office_slides_*`;
- GTD: `gtd_solo_all`, `gtd_wide`, `gtd_tall`, `gtd_support_*`,
  `gtd_review_*`, `gtd_mail_*`, `gtd_meeting_*`, `gtd_ai*`, `gtd_chat`, and
  `gtd_calendar`;
- display integration: `display_apply_solo`, `display_apply_wide_left`, and
  `display_apply_tall_left`;
- operations: `work_reload`, `work_status`, `work_mode_status`, `work_check`,
  `work_inventory`, `work_diagnostics`, `work_display_health`, `work_doctor`,
  `work_smoke`, `work_audit`, and `yabai_doctor`;
- observability/recovery: `workspace_snapshot`, `workspace_plan`,
  `workspace_verify`, `workspace_restore_labels`, and the documented explicit
  cleanup/recovery commands.

The history import will capture the exact manifest as the baseline. Any later
rename or removal requires a migration alias and release note.

## Behavioral Guarantees

### Dry-run

Every mutating public workspace entry keeps a `--dry-run` path that performs no
desktop mutation. Dry-run output may become more structured, but it must still
identify the command/workspace, display role, relevant apps/windows, layout,
and cleanup intent.

### Fail closed

Before mutation, the runtime returns non-zero without creating, relabeling,
moving, or destroying Spaces when:

- configuration is invalid or unsupported;
- jq or a required display query fails;
- a required primary window is absent;
- a target display role cannot be resolved safely.

### Display roles

Business-level workspace definitions do not embed display UUIDs. Fixed/control
workspaces resolve the configured primary role; external task workspaces
resolve the selected external/mode role.

### Labels and ownership

- Workspace labels are explicit and unique.
- Labeled Space preparation preserves ownership and retargets contaminated
  Spaces only through documented safe mechanics.
- Shared-window behavior remains explicit; no hidden precedence rule is added.
- Home and unmanaged-window Sandbox protections remain in force during
  finalization.

### Recovery

Retries and service recovery remain bounded and observable. No migration step
may introduce an unbounded retry, an implicit display change, or an automatic
repair in a command documented as read-only.

## Consumer Compatibility

Mackup continues to expose the existing command names to Fish and skhd. During
the pilot it can choose between:

- the legacy in-repository runtime; and
- a pinned SpaceWright build.

An emergency bypass restores the legacy path without rewriting user
configuration. The legacy runtime is removed only after configured paths pass
fixture checks, read-only checks, dry-run comparisons, and a real-use
observation period.

## Versioning

Before the first release, configuration has an explicit schema version.
SpaceWright releases state the supported schema range and any command-level
compatibility changes. Mackup pins an immutable release or commit rather than
implicitly following `develop`.

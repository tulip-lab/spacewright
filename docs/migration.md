# Migration Plan

## Objective

Move the existing Mackup-managed workspace runtime into SpaceWright without a
flag day, preserve relevant history, and leave personal configuration in
Mackup.

## Phase 0 — Contract And Inventory

Status: complete when this documentation set passes review.

- establish repository and git-flow rules;
- define provider/consumer ownership;
- inventory every source and integration area;
- freeze public command and safety compatibility;
- define publication/privacy checks and rollback gates.

No runtime code or desktop state changes occur in this phase.

## Phase 1 — History-Preserving Baseline Import

Work occurs on `feature/import-workspace-history` from `develop`.

### Selected import method

Use Git's built-in subtree tooling in a disposable clone:

1. clone the Mackup repository into a new directory under `/private/tmp`;
2. check out the recorded clean source commit in that disposable clone;
3. run `git subtree split` there with
   `.config/fish/functions/workspace` as the prefix;
4. import the resulting branch into SpaceWright below `legacy/workspace`
   without squashing;
5. retain the import merge ancestry and record both source commit ids;
6. remove the disposable clone only after the imported branch is verified.

Running the split in a disposable clone avoids adding temporary refs or
rewriting branches in the active Mackup repository. Importing without squash
keeps the relevant source ancestry. The `legacy/workspace` prefix prevents the
imported README and design notes from colliding with SpaceWright's product
documentation; later moves can be reviewed separately.

1. Recheck both worktrees and record the Mackup source commit.
2. Create a temporary history split of
   `.config/fish/functions/workspace/` without rewriting Mackup branches.
3. Import the split into an explicit legacy/source boundary in SpaceWright.
4. Preserve ancestry and record the source commit and import method.
5. Run Fish syntax and applicable read-only baseline checks.
6. Audit current files and imported history for sensitive or machine-specific
   material.

Rollback: abandon the feature branch. Mackup remains the active runtime and is
not modified by the split operation.

## Phase 2 — Relocatable Runtime

- introduce explicit package, configuration, and state roots;
- replace fixed `~/.config/fish/functions/workspace` source paths;
- inject display integration commands instead of assuming profile paths;
- validate from both the package checkout and a temporary install root;
- keep behavior changes out of the path-relocation commits.

Rollback: return to the imported baseline branch point. Mackup still owns the
active runtime.

## Phase 3 — Read-Only Configuration

- define version 1 JSON configuration and JSON Schema;
- merge package defaults with user configuration deterministically;
- implement configuration check/get/plan commands;
- compare config facts with the imported Fish manifest;
- reject invalid configuration before mutation.

No configured workspace is allowed to mutate state in this phase.

## Phase 4 — Pilot And Consumer Integration

- migrate `coding_editor_wide` behind an emergency legacy bypass;
- compare configured and legacy dry-run plans with fixtures;
- create a pinned development build or prerelease;
- add the Mackup consumer adapter and user configuration;
- run explicit live validation only after user authorization;
- expand to simple families only after the pilot is stable.

Rollback: switch Mackup to the legacy runtime and retain the same public
commands and hotkeys.

## Phase 5 — Packaging And Distribution

- add CI, semantic versioning, changelog, and release checks;
- add idempotent install, upgrade, doctor, and uninstall flows;
- preserve user configuration across install/uninstall;
- ship optional skhd and displayplacer examples;
- add a Homebrew formula only after the install layout stabilizes.

The repository remains private until a separate publication decision and a
complete history audit.

Acceptance for the first private prerelease is the scripted, marker-guarded
install layout, config-preserving uninstall, CLI, CI release check, semantic
version, changelog, optional integration examples, and immutable GitHub
prerelease. A Homebrew formula remains deliberately deferred until this layout
has survived prerelease upgrades.

## Phase 6 — Full Configuration Parity

- configure every coding, research, Office, and GTD workspace;
- encode ordered solo/wide/tall aggregate composition;
- route public entries through a closed set of configured runners;
- retain specialized Fish recovery adapters for Office and GTD behavior;
- generate read-only observation contracts for every configured workspace;
- compare every configured workspace and mode dry-run with the imported
  definition;
- keep `SPACEWRIGHT_CONFIG_DISABLE=1` as the whole-runtime rollback switch;
- release and update the Mackup consumer pin only after package checks and
  authorized live validation pass.

Phase 6 deliberately configures facts without translating recovery programs
into JSON. This preserves the pre-extraction behavior while making personal
apps, labels, layouts, and composition consumer-configurable.

## Cross-Repository Delivery Order

For a change spanning both repositories:

1. implement and validate SpaceWright on a feature branch;
2. merge it through SpaceWright's git-flow process;
3. create an immutable commit, prerelease, or release reference;
4. update Mackup configuration and version pin on its own branch;
5. validate the consumer path and rollback path;
6. merge and push the Mackup change separately.

Never stage files from both repositories into one commit.

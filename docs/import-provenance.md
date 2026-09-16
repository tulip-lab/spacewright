# Import Provenance

## Baseline

- Source repository: Mackup (private local consumer repository)
- Source commit: `a8954fa18d3fb4f685dfc70afbfe630996cb3898`
- Source prefix: `.config/fish/functions/workspace`
- Split commit: `122fe295d471f7db63e92470b06091e52f946609`
- Destination prefix: `legacy/workspace`
- Import commit: `4b66ae5`
- Import mode: Git subtree without squash

The split ran in a disposable clone below `/private/tmp`; no temporary branch or
history rewrite was created in the active Mackup repository.

## Verification

- All 63 source files matched the imported tree byte-for-byte immediately
  after import.
- All 61 imported Fish files passed `fish -n`.
- The imported ancestry contains 80 filtered commits.
- A focused current-tree and history scan found no private-key marker, common
  assigned credential pattern, or absolute `/Users/...` path.
- References to `WORKSPACE_PRIMARY_DISPLAY_UUID` are code-level state access,
  not embedded UUID values.

This audit is evidence for the private baseline import only. A broader secret,
license, fixture, and metadata audit remains mandatory before any future public
release.

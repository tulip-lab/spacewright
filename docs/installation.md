# Installation and upgrades

## Requirements

- macOS
- Fish 3.6 or newer
- `jq`
- `yabai` for live workspace commands

`skhd` and `displayplacer` remain optional integrations.

## Install from a trusted checkout

For this private prerelease, clone or update the repository through your
authenticated GitHub access, check out the desired immutable tag, and run:

```fish
fish scripts/install.fish
```

The installer copies the tagged build to:

```text
~/.local/share/spacewright/releases/<version>
```

It then atomically points `current` at that version and creates managed links
for Fish startup and `~/.local/bin/spacewright`. Existing non-managed files or
links are never overwritten.

The installer does not create, replace, or remove
`~/.config/spacewright/config.json`. Re-running it for the same version is
idempotent. Installing a newer tagged checkout changes `current`; older release
directories remain available for rollback.

## Verify

```fish
spacewright version
spacewright config-check
spacewright config-plan coding_editor_wide
spacewright doctor
```

These checks are read-only. A live workspace command remains a separate,
explicit action.

## Roll back

Point `~/.local/share/spacewright/current` to an earlier installed release, or
set `SPACEWRIGHT_CONFIG_DISABLE=1` to use the built-in definition for the
configured pilot. Mackup's consumer adapter also supports
`SPACEWRIGHT_USE_LEGACY=1` to load its retained legacy runtime.

The installed Fish bootstrap honors `SPACEWRIGHT_USE_LEGACY=1` by returning
without loading SpaceWright, allowing the consumer adapter to take over.

## Uninstall

```fish
fish scripts/uninstall.fish
```

The uninstaller removes only links and package files carrying SpaceWright's
install marker. User configuration and state are preserved. Use
`--keep-packages` to remove activation links while retaining downloaded
releases.

Both scripts accept `--dry-run`; `--prefix`, `--fish-config-root`, and
`--bin-root` make isolated or managed installations possible.

## Homebrew

A formula is intentionally deferred until the install layout and private
distribution workflow have survived the prerelease cycle. The scripted layout
is the Phase 5 distribution contract.

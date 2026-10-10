# Installation and upgrades

## Requirements

- macOS
- Fish 3.6 or newer
- `jq`
- `yabai` for live workspace commands
- Node.js 20 or newer for the Web Configurator and v2 compilation; normal
  workspace commands do not require it once the compiled runtime is current

`skhd` and `displayplacer` remain optional integrations.

New Homebrew users should follow [Getting started](getting-started.md) for the
required yabai permission, personal app registration, display binding,
workspace layout, dry-run, and first live-run steps.

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
`~/.config/spacewright/config.json` or `config.v2.json`. Re-running it for the same version is
idempotent. Installing a newer tagged checkout changes `current`; older release
directories remain available for rollback.

## Verify

```fish
spacewright version
spacewright config-check
spacewright config-compile
spacewright config-status
spacewright config-plan coding_editor_wide
spacewright doctor
spacewright configure
```

These checks are read-only. A live workspace command remains a separate,
explicit action.

`spacewright doctor` distinguishes a current v2 runtime from a missing or
stale compiled runtime. It never recompiles or changes configuration.

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

## Install with Homebrew

The supported public distribution is the `tulip-lab/homebrew-tap` formula:

```sh
brew install tulip-lab/tap/spacewright
```

The release archive contains Fish and JavaScript source rather than native
machine code. The same archive supports Apple Silicon and Intel Macs; Homebrew
selects compatible bottles for the `fish`, `jq`, and `node` dependencies.
SpaceWright itself does not need separate architecture-specific artifacts.

`yabai` is not in Homebrew Core and is deliberately not an automatic formula
dependency. Install and configure it from its official tap before running live
workspace commands. Read-only configuration commands remain useful without it.

Upgrade and uninstall through Homebrew in the usual way:

```sh
brew update
brew upgrade spacewright
brew uninstall spacewright
```

Homebrew keeps user configuration and machine state outside its Cellar, so an
upgrade or uninstall does not delete either one.

Continue with [Getting started](getting-started.md) to create and validate the
user's personal configuration before running a live workspace command.

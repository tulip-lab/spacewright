# Getting started

This guide is for a new SpaceWright user installing a published release on a
Mac. SpaceWright does not copy the maintainer's private workspace definitions:
each user creates portable configuration for their own apps and layouts, then
binds that configuration to the displays connected to their Mac.

## 1. Prepare macOS and yabai

SpaceWright requires macOS and uses yabai to inspect and arrange windows,
Spaces, and displays. Install yabai from its maintained Homebrew tap:

```sh
brew install asmvik/formulae/yabai
yabai --start-service
```

Allow yabai under **System Settings → Privacy & Security → Accessibility** when
macOS prompts. Some Space creation, movement, and ordering features also require
the yabai scripting addition and the corresponding macOS security setup. Follow
the current [yabai installation guide](https://github.com/asmvik/yabai/wiki/Installing-yabai-%28latest-release%29)
rather than copying an old sudoers or System Integrity Protection command.

In **System Settings → Desktop & Dock → Mission Control**, disable
**Automatically rearrange Spaces based on most recent use** so configured Space
ordering remains stable.

## 2. Install SpaceWright

After the first public SpaceWright release is available:

```sh
brew install tulip-lab/tap/spacewright
```

The formula installs SpaceWright together with Fish, jq, and Node.js. It uses
the same SpaceWright release on Apple Silicon and Intel Macs.

Confirm the installation without changing the desktop:

```sh
spacewright version
spacewright doctor
```

`spacewright doctor` is read-only. Resolve any reported yabai, Accessibility,
configuration, or display-binding problem before running a live layout.

## 3. Create personal configuration

Open the local configurator:

```sh
spacewright configure
```

The configurator listens only on the local Mac and opens in the default
browser. Saving configuration does not move windows, create Spaces, apply a
display profile, or reload a shortcut service.

Complete these pages for the current user:

1. **Apps** — register every application used by a workspace. Use read-only app
   discovery to capture the names reported by yabai and add aliases when one app
   can appear under more than one name.
2. **AI Routing** — optionally select the provider used by each semantic AI
   role and add mode-specific overrides only where needed.
3. **Display roles** — create portable roles such as `primary`, `wide`, or
   `tall`, discover connected displays, and bind each role to the correct
   display on this Mac. Display UUID bindings are machine-local and must be
   repeated on another Mac.
4. **Workspaces** — define stable workspace IDs, Space labels, required and
   optional windows, and the selector that identifies each window.
5. **Layouts** — arrange windows for Solo, Wide, and Tall variants. A required
   window must appear in every applicable layout; optional windows may be
   omitted.
6. **Modes** — place workspaces in their desired order on each display role.
   This lane order controls both execution and final Space ordering.
7. **Shortcuts** — optionally create structured SpaceWright shortcuts. Saving
   generates a fragment; the user must explicitly include that fragment from
   their own skhd configuration.
8. **Review** — resolve validation errors and inspect warnings, then save.

Portable configuration is stored at:

```text
~/.config/spacewright/config.v2.json
```

The compiled runtime is stored below the same configuration directory. Local
display bindings, observations, and transition history are stored separately
under the user's state directory and should not be copied between Macs.

## 4. Validate before changing the desktop

Run the read-only checks after saving:

```sh
spacewright config-v2-check
spacewright config-status
spacewright doctor
spacewright inspect
```

Preview a complete mode transition:

```sh
spacewright mode solo --dry-run
spacewright mode wide --dry-run
spacewright mode tall --dry-run
```

Preview one configured workspace by replacing the placeholders with IDs from
the configurator:

```sh
spacewright plan <workspace-id> <solo|wide|tall>
spacewright workspace <workspace-id> <solo|wide|tall> --dry-run
```

Do not continue to a live command while a preview reports an unavailable
display, missing required window, ambiguous match, stale runtime, or yabai
query failure.

## 5. Run SpaceWright

Once the matching apps are open and the preview is correct, activate a full
mode:

```sh
spacewright mode solo
spacewright mode wide
spacewright mode tall
```

Or arrange one workspace:

```sh
spacewright workspace <workspace-id> <solo|wide|tall>
```

The progress banner reports the active phase. Use these commands if a run needs
attention:

```sh
spacewright mode-status
spacewright mode-cancel
spacewright transition-history
```

The configurator's **Current state** and **Run & tasks** pages provide the same
preview-first workflow in the browser.

## 6. Upgrade or uninstall

Upgrade to the latest published version:

```sh
brew update
brew upgrade spacewright
spacewright version
spacewright doctor
```

Uninstall the package with:

```sh
brew uninstall spacewright
```

Homebrew upgrades and uninstallations do not remove personal configuration or
machine-local state. Back up `~/.config/spacewright/config.v2.json` separately
if the configuration should be retained outside this Mac.

## Troubleshooting order

When a layout does not run as expected:

1. open every required application window;
2. run `spacewright doctor`;
3. run `spacewright config-status`;
4. inspect the relevant `--dry-run` output;
5. check app aliases, window selectors, and display bindings in
   `spacewright configure`;
6. review `spacewright transition-history` before retrying a live command.

Do not start by weakening validation or copying another Mac's display UUIDs.

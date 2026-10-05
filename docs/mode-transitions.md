# Mode Transitions

`spacewright mode <solo|wide|tall>` is the interactive entry point for a full
display-and-workspace change. Use it from skhd and other launchers instead of
chaining `display_apply_*; work_*` directly.

## Interaction model

- One transition owns the desktop at a time through the shared atomic execution
  lock under the SpaceWright state root. CLI and Web Configurator mutations use
  that same lock and therefore cannot overlap a shortcut-triggered switch.
- Repeating the active mode is coalesced into the existing run. It never starts
  a second layout pass.
- Requesting a different mode cancels the old process group and starts the new
  choice. The most recent deliberate choice therefore wins.
- A transition stops after 120 seconds by default. Set
  `SPACEWRIGHT_MODE_TIMEOUT_SECONDS` to a positive number to change this safety
  deadline.
- `spacewright mode-cancel` stops the active transition and
  `spacewright mode-status` reports its latest persisted state.

The controller owns both the display profile and the aggregate workspace run,
so they cannot overlap with another controller-managed mode switch. Existing
Fish functions remain available for compatibility, but a compound shortcut
that calls them directly does not gain controller semantics and should be
migrated.

## Progress banner

Installed macOS builds compile a small AppKit helper. While a transition is
active it presents a non-activating, always-on-top banner near the top of the
current display. The banner shows:

- the requested mode;
- the current `workspace_run_step` label;
- elapsed time and the safety-stop countdown;
- a Stop control that cancels the complete child process group.

Success, replacement, cancellation, timeout, and failure use distinct terminal
colors and dismiss automatically. The banner is feedback only: inability to
show it never grants permission to mutate or weakens the lock. Set
`SPACEWRIGHT_BANNER_DISABLE=1` for headless automation.

## Recommended skhd bindings

```text
ctrl + alt - w : fish -lc 'spacewright mode wide'
ctrl + alt - t : fish -lc 'spacewright mode tall'
ctrl + alt - s : fish -lc 'spacewright mode solo'
ctrl + alt - escape : fish -lc 'spacewright mode-cancel'
```

`spacewright mode MODE --dry-run` prints the complete closed operation without
acquiring a lock, displaying a banner, or changing the desktop.

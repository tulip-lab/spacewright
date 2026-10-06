# Mode Transitions

`spacewright mode <solo|wide|tall>` is the interactive entry point for a full
display-and-workspace change. Use it from skhd and other launchers instead of
chaining `display_apply_*; work_*` directly.

`spacewright workspace <workspace-id> <solo|wide|tall>` is the corresponding
interactive entry point for one workspace. It uses the same lock, cancellation,
deadline, status, and progress banner, but deliberately skips mode-wide Sandbox
collection, Space ordering, and finalization. It only runs the selected
workspace and its bounded opposite-variant cleanup.

## Interaction model

- One transition owns the desktop at a time through the shared atomic execution
  lock under the SpaceWright state root. CLI and Web Configurator mutations use
  that same lock and therefore cannot overlap a shortcut-triggered switch.
- Repeating the active mode or individual workspace is coalesced into the
  existing run. It never starts a second layout pass.
- Requesting a different mode or workspace cancels the old process group and
  starts the new choice. The most recent deliberate choice therefore wins.
- A transition stops after 120 seconds by default. Set
  `SPACEWRIGHT_MODE_TIMEOUT_SECONDS` to a positive number to change this safety
  deadline.
- `spacewright mode-cancel` stops the active transition and
  `spacewright mode-status` reports its latest persisted state.
- `spacewright transition-history` returns the recent guarded transitions as
  JSON. The state root retains at most 100 entries under
  `transition-history/`, including duration, warnings, skipped/unavailable app
  signals, failure details, and a bounded output tail.

The controller owns both the display profile and the aggregate workspace run,
so they cannot overlap with another controller-managed mode switch. Existing
The historical `work_solo`, `work_wide`, and `work_tall` functions and the
individual workspace functions remain available as compatibility names. When
called directly with normal configuration enabled, they now route through the
same guarded CLI. Internal aggregate execution and the explicit legacy bypass
continue to use their tested Fish bodies without recursively starting another
controller.

## Progress banner

Installed macOS builds compile a small AppKit helper. While a transition is
active it presents a non-activating, always-on-top banner near the top of the
current display. Its fixed dark, high-contrast surface remains readable over
light or visually busy desktop content. The banner shows:

- the requested mode or individual workspace;
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
fn + shift - 9 : fish -lc 'spacewright workspace gtd_ai solo'
```

`spacewright mode MODE --dry-run` prints the complete closed operation without
acquiring a lock, displaying a banner, or changing the desktop.
`spacewright workspace ID MODE --dry-run` reports the target-scoped policy and
likewise makes no desktop changes.

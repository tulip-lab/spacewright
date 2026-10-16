# Mode Transitions

`spacewright mode <solo|wide|tall>` is the interactive entry point for a full
display-and-workspace change. Use it from skhd and other launchers instead of
chaining `display_apply_*; work_*` directly.

`spacewright workspace <workspace-id> <solo|wide|tall>` is the corresponding
interactive entry point for one workspace. It uses the same lock, cancellation,
deadline, status, and progress banner, but deliberately skips mode-wide Sandbox
collection, Space ordering, and finalization. It only runs the selected
workspace through the same immutable apply plan used by the CLI and Web.
Single-workspace execution explicitly plans only that workspace's empty opposite
variant UUIDs. It rechecks complete discovery, labels, display and occupancy
before deletion; other workspaces and user Spaces are outside its scope. A global
post-shortcut cleanup hook is not appended after the verified local plan.

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
so they cannot overlap with another controller-managed mode switch. The historical `work_solo`, `work_wide`, and `work_tall` functions and the
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

`spacewright mode MODE --dry-run` runs the same read-only configuration, binding,
discovery, selector and executable-profile checks, then prints the planned
display and layout stages without acquiring a lock, displaying a banner, or changing the desktop.
`spacewright workspace ID MODE --dry-run` reports the target-scoped policy and
likewise makes no desktop changes.

## Verification and cancellation

Interactive mode requests run the display and layout phases in the shared apply
engine under one inherited lease and total deadline. Read-only preflight rejects
invalid configuration, missing bindings, incomplete discovery and unrecoverable
required-window failures before the display profile. Declared adapter recovery
remains deferred until after the display phase. Source and machine generations
are rechecked immediately before display mutation. The profile runs once, then
fresh discovery and setup resolution precede layout; logs distinguish preflight,
display start/completion and layout failure.

For v3, preflight projects a unique already-confirmed target setup with connected
physical bindings, allowing its orientation to differ from the current display.
Ambiguous targets, unconfirmed setups and unsupported physical combinations
are rejected without adding confirmations. The live resolver checks the real
after-display snapshot. There is no automatic display rollback.

Success requires the verified-convergence marker. Ordinary errors,
verification failure and timeout are terminal failures; diagnostic history
retains the last step and output. The inherited total deadline also bounds child
commands. Cancellation and replacement stop all registered process groups,
escalate an unresponsive child, and only then release the execution lease.
Direct `run`, `display`, `focus`, `order`, `finalize` and `postprocess` use the
same lease. CLI scripts start Fish without personal startup configuration;
consumer configuration is loaded through the documented configuration roots.

## Preparation and interruption

Native fullscreen exit or observed complex-app refresh appears in the apply
preview as a preparation phase, with possible replacement/window-creation side
effects. The controller persists its relationship to the rediscovered layout
plan. It does not silently substitute an ID during layout. Existing optional
windows failing placement still fail the transition.

After a bounded Space visit fails to restore yabai window references (for
example after an app update), the declared fallback may restart yabai once,
restore labels/settings by Space UUID and replan before layout. The progress
banner shows the recovery phase. Interrupted recovery leaves a durable
checkpoint with an explicit `spacewright repair-yabai --resume=RUN_ID` command;
later applies cannot continue while restoration is unfinished. See
[State discovery and reconciliation](state-reconciliation.md).

The two known ChatGPT desktop-controller accessory windows, `Computer Use` and
`Computer Use Controls`, may appear/disappear during testing without invalidating
an aggregate layout. Recognition also requires their AX role, non-resizable
capability and verified bounded native frame. They remain in full discovery and
Space occupancy checks and are excluded from ordinary application-role selection;
explicitly selected windows and ordinary dialogs,
including permission prompts, retain the normal identity guards.

The transition lease owns the total deadline and configured retry/recovery
counters; child processes cannot extend them. Cancellation marks the shared run
before stopping children, and a pipe gate prevents a child from executing until
its process-group identity has been registered. Recovery journals distinguish
unknown attempts and verified results, and exclude unoperated selections.

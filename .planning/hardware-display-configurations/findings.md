# Findings

- v2 restricts both modes and workspace variants to `solo`, `wide`, and `tall`.
- Existing profiles select one of those modes rather than representing hardware or arbitrary display setups.
- Portable display roles are already separated from machine-local UUID bindings in `machine.json`.
- Runtime compilation already produces a digest-bound normalized plan; v3 should compile into that boundary where practical.
- Existing topology rules recognize several shapes but do not resolve hardware family plus a user-confirmed setup.
- Existing display resolution has fail-closed behavior when the primary display is unknown or absent.
- A background Fish login shell can resolve an older installed `spacewright` from
  `PATH` while testing a repository checkout. Transition commands must source and
  invoke the explicit package root to keep runtime code and configuration aligned.
- Hardware-specific configurations are required even when layouts are visually
  identical: a MacBook tall configuration targets a non-primary external display,
  while a Mac mini single-tall configuration must target its sole primary display.
- Legacy modes may omit configured workspaces from their lane order. Migration
  must complete every setup from the full workspace inventory rather than treating
  legacy placement as an exhaustive list.
- Shared apps require dependency-aware reconciliation: if an earlier workspace
  touches a window owned by a later workspace, the later owner must be reapplied.
- A confirmed hardware profile and active setup provide a stable, user-visible
  identity for transition feedback; compatibility mode alone is insufficient.

# Security And Publication

## Current Policy

SpaceWright is private during extraction and hardening. MIT licensing does not
itself authorize publication; making the repository public is a later explicit
decision.

## Import Audit

Before importing history, identify and review:

- credentials, tokens, private keys, authentication files, and session data;
- usernames, home-directory paths, hostnames, device identifiers, and display
  UUIDs;
- personal application/workflow names that should become configuration;
- private URLs, organization information, or internal filesystem locations;
- logs, caches, screenshots, generated runtime state, and temporary files;
- third-party code or assets whose license is not compatible with MIT.

The import must be limited to the reviewed workspace subtree. Adjacent dotfiles
are not included merely because the runtime currently calls them.

## Runtime Data Rules

- Never log secrets or full environment dumps.
- Keep runtime state outside the package and user configuration roots.
- Treat yabai snapshots as potentially sensitive because window titles may
  contain personal or professional information.
- Fixtures must use synthetic app names, titles, identifiers, and geometry
  unless a reviewed real value is necessary.
- Doctor/debug output should report enough context to diagnose a failure
  without exposing unrelated window titles or configuration secrets.

## Public Release Gate

Before any visibility change from private to public:

1. scan the current tree and complete history for secrets;
2. inspect author metadata and rewritten/imported paths;
3. replace personal defaults with sanitized examples;
4. verify all dependencies and bundled assets have compatible licenses;
5. verify README, security guidance, installation, uninstall, and rollback;
6. run CI and a clean-clone install/read-only diagnostic test;
7. obtain an explicit publication decision from the repository owner.

If history contains material that cannot be published, create and review a
sanitized history before changing visibility. Do not assume deletion from the
latest tree removes data from Git history.

## Destructive And Live-State Operations

Read-only tests are the default. Commands that move windows, create or destroy
Spaces, change display geometry, restart services, or rewrite Git history
require an explicit scope and rollback plan. Publication work must never use a
history rewrite against Mackup's active branches.

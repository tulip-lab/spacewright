# Security And Publication

## Current Policy

SpaceWright became public on 2026-10-07 after the maintainer requested public
Homebrew distribution and the review below completed. MIT licensing does not
replace the publication review. Public Homebrew installation requires the
source repository and its release assets to remain anonymously readable.

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

## 2026-10-07 publication review

The Homebrew distribution work performed the following non-mutating checks:

- scanned all reachable Git history with Gitleaks using redacted reporting;
  no credential findings were reported;
- searched the current tree and patches for private-key markers, common token
  formats, absolute `/Users/...` paths, and embedded display UUID values;
- inventoried historical paths for credentials, sessions, logs, databases,
  caches, private keys, and generated state;
- confirmed the distributable allowlist excludes Git metadata, tests,
  `AGENTS.md`, `node_modules`, caches, and machine state;
- confirmed the only direct npm package is the Playwright test dependency and
  neither it nor its transitive packages are bundled in the release artifact;
- confirmed the repository declares MIT and the release contains no compiled
  third-party artifact.

No secret or machine-specific identifier was found. The Git history does expose
the maintainer name and the addresses `gangli@duck.com` and
`4224559+tuliplab@users.noreply.github.com`. Changing repository visibility is
the maintainer's explicit acceptance of publishing that metadata.

The complete read-only release check and release-archive inspection passed
before the visibility change. GitHub secret scanning and push protection were
enabled immediately afterward. The public history intentionally retains the
reviewed maintainer metadata listed above.

## Destructive And Live-State Operations

Read-only tests are the default. Commands that move windows, create or destroy
Spaces, change display geometry, restart services, or rewrite Git history
require an explicit scope and rollback plan. Publication work must never use a
history rewrite against Mackup's active branches.

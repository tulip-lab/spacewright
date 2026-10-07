# Release process

## Distribution model

SpaceWright uses a dedicated Homebrew tap rather than Homebrew Core while the
project is in prerelease. The source repository owns validation and release
artifacts; `tulip-lab/homebrew-tap` owns the generated formula.

There is no native compilation step. The distributable is an
architecture-independent `spacewright-<version>.tar.gz` containing the Fish
runtime, JavaScript configurator, schemas, examples, installer, and docs. A
tagged release also publishes `SHA256SUMS`.

The version authority is the root `VERSION` file. A release tag must be exactly
`v` followed by that value. Versions containing a hyphen, such as
`0.2.0-alpha.12`, are published as GitHub prereleases; versions without one are
published as normal releases.

## What the tag workflow does

`.github/workflows/release.yml` runs on every `v*` tag and:

1. rejects a tag that does not match `VERSION`;
2. runs the complete macOS release checks;
3. builds the architecture-independent archive and SHA-256 checksum file;
4. creates the GitHub Release, or safely replaces assets when rerun;
5. renders `Formula/spacewright.rb` with the immutable release URL and digest;
6. commits and pushes that formula to `tulip-lab/homebrew-tap`.

The tap checkout authenticates with the repository secret
`HOMEBREW_TAP_DEPLOY_KEY`. It must be an SSH deploy key with write access only
to `tulip-lab/homebrew-tap`; do not use a broad personal access token.

## One-time maintainer setup

Complete these steps once before pushing the first public release tag:

1. Complete and record the publication gate in
   `security-and-publication.md`. In particular, consciously accept that Git
   author names and email addresses become public history.
2. Make `tulip-lab/spacewright` public. Homebrew cannot anonymously download
   release assets from a private repository.
3. Create the public `tulip-lab/homebrew-tap` repository with a `Formula/`
   directory and default branch `main`.
4. Generate a dedicated SSH key with no passphrase. Add the public half as a
   write-enabled deploy key on `tulip-lab/homebrew-tap`, and add the private
   half as the `HOMEBREW_TAP_DEPLOY_KEY` Actions secret on
   `tulip-lab/spacewright`.
5. Keep the repository's default Actions token permission read-only. The
   release workflow elevates only its own token to `contents: write`, which is
   sufficient to create releases.
6. Merge this distribution work through `develop` and `main` before creating
   the first tag. A tag created from a commit without the release workflow will
   not publish Homebrew artifacts.

After the first workflow succeeds, verify from a Mac that does not have a
development checkout:

```sh
brew update
brew install tulip-lab/tap/spacewright
spacewright version
spacewright config-v2-check "$(brew --prefix spacewright)/libexec/examples/config-v2.json"
brew test tulip-lab/tap/spacewright
```

## Publish the first release

SpaceWright follows git-flow. Replace `<version>` below with the final value,
for example `0.2.0-alpha.12`; do not tag a `-dev...` version.

```sh
git switch develop
git pull --ff-only origin develop
git switch -c release/<version>
```

On the release branch:

1. replace the root `VERSION` value with `<version>`;
2. move the release notes in `CHANGELOG.md` under that exact version;
3. run `fish scripts/check.fish` and `git diff --check`;
4. commit the version and changelog changes.

Then merge the release branch into `main` and `develop` according to the
repository git-flow policy. On the resulting `main` commit:

```sh
git tag -s v<version> -m "SpaceWright <version>"
git push origin main develop v<version>
```

An annotated tag is acceptable when signing is not configured. Watch the
`Release` workflow until both the GitHub Release and tap commit succeed, then
run the clean-machine verification above.

## Publish subsequent upgrades

Every later upgrade uses the same release-branch steps: update `VERSION` and
`CHANGELOG.md`, merge to `main` and `develop`, then push the matching tag. No
checksum or formula edit is manual.

Users receive the upgrade through:

```sh
brew update
brew upgrade spacewright
```

Never retag a different commit. If a release is wrong, fix it in a new version
and tag; the old formula commit and release asset remain an auditable rollback
point.

## Local packaging check

To inspect the exact artifacts without publishing:

```fish
set release_tag v(string trim < VERSION)
fish scripts/package-release.fish --tag "$release_tag" --output /tmp/spacewright-dist
shasum -a 256 -c /tmp/spacewright-dist/SHA256SUMS
```

The full release check also exercises formula rendering:

```fish
fish scripts/check.fish
```

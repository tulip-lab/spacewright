# Release process

SpaceWright follows git-flow:

1. branch `release/<version>` from `develop`;
2. update `VERSION` and `CHANGELOG.md`;
3. run `fish scripts/check.fish` from a clean checkout;
4. merge the release branch into both `main` and `develop`;
5. create a signed or annotated `v<version>` tag on `main`;
6. push both branches and the tag;
7. create a private GitHub prerelease with the changelog entry;
8. update the consumer repository's immutable version pin.

Do not publish the repository or release assets publicly without completing
the separate privacy and rights gate in `security-and-publication.md`.

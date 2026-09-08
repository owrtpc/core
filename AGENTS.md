# OWRTPC contributor and agent instructions

Use this repository as the working directory. Preserve unrelated local edits.

## Release ordering (mandatory)

- Every distributed APK must be built only after its source changes have been
  committed with a DCO Signed-off-by trailer and pushed to origin/main.
- Run tests and wait for successful CI before building a release. Use
  scripts/build-signed-apk.sh; never bypass its preflight check.
- A clean worktree, including untracked files, is required. The live remote
  main commit must equal HEAD. Offline release builds are not allowed.
- For a new package revision, increment PKG_RELEASE. When PKG_VERSION changes,
  reset PKG_RELEASE to 1, following OpenWrt conventions. Update the changelog
  before the release commit. Never overwrite a distributed package version.
- Keep the APK, its .sha256 and .buildinfo together. Never commit private keys.
- A failed check is a reason to stop the release, not to disable the check.
- Do not commit or push for unrelated tasks without user authorization.
  If release work needs a commit/push not already authorized, ask first.

See CONTRIBUTING.md and docs/DEVELOPMENT.md for the workflow and test commands.

# Contributing to OWRTPC

Thank you for helping improve OWRTPC. Bug reports, device test results,
documentation improvements and focused code changes are welcome.

## Before opening an issue

- Search existing issues for the same problem.
- Confirm that flow offloading is disabled.
- Run `owrtpcctl validate` and include its output.
- Include the OpenWrt release, target, device model and relevant logs.
- Remove MAC addresses, public IP addresses and other private information.

Do not report security vulnerabilities in a public issue; follow
[SECURITY.md](SECURITY.md) instead.

## Development workflow

1. Create a feature branch from `main`.
2. Keep each commit focused on one logical change.
3. Run `./tests/run.sh` before submitting the change.
4. Test on an OpenWrt 25.12+ device or with the documented Docker environment
   when the change affects runtime behavior.
5. Open a pull request explaining the behavior, rationale and test coverage.

Follow the coding style of the surrounding files. LuCI translations must
eventually be managed through OpenWrt Weblate; do not add hand-maintained
translation catalogs.

## Commit messages and Developer Certificate of Origin

Use an OpenWrt-style subject prefixed with the affected component. The text
after the colon starts with a lowercase letter, for example:

```text
owrtpc: account shared profile usage
```

Explain what changed and why in the commit body. Keep the subject and body
lines reasonably short.

Every commit must include a `Signed-off-by` trailer certifying the
[Developer Certificate of Origin](https://developercertificate.org/). Use your
real first and last name and a real email address; GitHub private/noreply
addresses are not accepted by OpenWrt. Create the trailer with:

```sh
git commit --signoff
```

By signing off, you certify that you have the right to submit the contribution
under this repository's Apache-2.0 license.

## Release discipline

Every change included in a distributed APK must be committed and pushed first.
Use the sequence: tests, DCO-signed commit, push, successful CI, signed build.
Do not generate a release from a dirty checkout or an unpushed commit, and do
not overwrite an already distributed version. See
[the release workflow](docs/DEVELOPMENT.md#signed-release-apks).

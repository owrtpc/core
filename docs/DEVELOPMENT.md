# Development

## Two packages, one repository

Use `https://github.com/owrtpc/core`. Clone the existing repository; do not create
replacement history. After the organization owner renames the GitHub repository,
update an existing clone with:

```sh
git remote set-url origin git@github.com:owrtpc/core.git
git ls-remote origin refs/heads/main
```

Keep backend and LuCI together. The `owrtpc/mobile` client uses a separate
repository and a pinned Docker-first Flutter toolchain; its platform spike can
advance without adding mobile SDKs to this core repository. No standalone LuCI
repository or official feed submission is planned.

## Buildroot / SDK conventions

Backend uses OpenWrt `package.mk`, explicit runtime dependencies, conffiles and
`INSTALL_*` macros. The UI uses `luci.mk`, `LUCI_DEPENDS`, JS views, JSON menus,
`htdocs/`, `root/` and `po/`. Shared RPC ACLs reside in the backend, including a
legacy grant alias. LuCI has no service, configuration file or engine payload.

Link both packages into an OpenWrt 25.12+ tree with the LuCI feed installed:

```sh
ln -s /path/to/core/owrtpc package/owrtpc
ln -s /path/to/core/luci-app-owrtpc package/luci-app-owrtpc
make menuconfig
# Network > owrtpc; optionally LuCI > Applications > luci-app-owrtpc
make package/owrtpc/compile package/luci-app-owrtpc/compile V=s
```

The standalone discovery dependency `rpcd-mod-luci` is in the LuCI *source
feed*, but does not require its web interface. Install the source definitions
from the pinned SDK feeds even when building backend alone.

For the existing local Docker SDK (`owrtpc-sdk-25.12.5` volume and
`owrtpc-sdk-builder:25.12.5` image), run `scripts/setup-sdk.sh` from the SDK root
once to install base/LuCI package definitions. The SDK directory is
`/build/openwrt-sdk-25.12.5-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64`.
`scripts/sdk-build.sh` fails if required definitions are absent.

The packaging-only SDK helper disables minification and uses OpenWrt's
`NO_DEPS=1` target traversal because these two packages contain only shell, JS
and data, with no compiled translations. It preserves normal dependency
metadata and does not suppress compile errors, APK dependency checks or
signature checks. Future native code or translated catalogs require revisiting
this helper and building the relevant host/target prerequisites.

## Local verification

```sh
./tests/run.sh
node tests/release.test.js
node tests/packaging.test.js
sh scripts/build-test-apks.sh
OWRTPC_OVERLAY=none OWRTPC_IMAGE=owrtpc-openwrt-base:25.12.5 ./docker/build-image.sh
sh docker/test-packages.sh
```

Development APKs go only to ignored `tmp/test-apks/`, are not signed with the
release key, and must not be distributed. The lifecycle suite uses real APK
installation and scripts: clean backend/UI install, removal of the UI without
restarting the backend, a system with all of LuCI removed, restricted rpcd
login/ACL checks, actual host hints, policy tests and migration from the real
signed r20 APK in `dist/`, plus upgrade from the signed split r22 pair. Preserve
these historical artifacts. CI runs clean/headless cases without those binaries.

The lifecycle suite also tests full reset with and without LuCI: explicit
confirmation, write ACLs, pending changes/snapshots, busy locks, missing defaults,
symlink refusal, preserved router config and state not returning after restart.
`tests/reset.test.js`, invoked by `tests/run.sh`, exercises the LuCI dialog's
cancel/confirm, read-only access, double click and error paths with a mocked DOM.
Actual browser rendering still requires the Docker UI workflow.

See [docker/README.md](../docker/README.md) for UI smoke tests and container
limitations. Tests never connect to a physical router.

CI has two jobs: source/release safeguards and SDK builds with clean/headless
APK lifecycle tests. The package job uses `ubuntu-24.04-arm`: OpenWrt and its
nftables tests run on native ARM64. QEMU user mode does not support
`NETLINK_NETFILTER`, so emulating the router userspace on an x86 runner cannot
verify the firewall. Only the official x86_64 SDK tools run under emulation,
inside `docker/sdk.Dockerfile`; no firewall assertions are skipped.
`sh scripts/ci-packages.sh` reproduces that job on a native ARM64 Docker host.
SDK/firmware downloads use pinned SHA-256 values. It does
not publish unsigned APKs. The historical r20 binary is deliberately not
reconstructed or committed as a fixture: migration against that actual binary
is a local release verification requirement.

## Signed release APKs

Public key: `keys/owrtpc-release.pem`. Private key defaults to
`~/.config/owrtpc/signing/private-key.pem`, overridable with `OWRTPC_SIGNING_KEY`.
Never commit or rotate it as part of the package split.

Required order:

1. Increment `PKG_RELEASE` in both Makefiles and update `CHANGELOG.md`. Never
   reuse an already distributed version. r22 is the first split release.
2. Run source tests, build ephemeral test APKs and pass the Docker lifecycle
   suite including migration from the historical package.
3. Commit with `git commit --signoff`, push `main` and wait for **all CI jobs**
   on that exact commit to succeed.
4. From clean `main` run:

   ```sh
   sh scripts/check-release.sh
   ./scripts/build-signed-apk.sh
   ```

The preflight checks clean status including untracked files, branch, DCO, the
live remote main SHA, and the latest successful push CI run for the exact SHA
in `owrtpc/core`. Network/CI failures stop the release; there is no bypass.
Python 3 is required for the GitHub CI query. The build never commits or pushes.

The builder exports a committed snapshot of both packages and the SDK helper,
signs both APKs with the same stable key, verifies both signatures and only
then copies results into `dist/`. Existing APKs or sidecars block the entire
build. Each APK has `.sha256` and `.buildinfo` sidecars with source repository,
commit, SDK/image and build time. Preserve all three files per package. Check
previous distributions too: the overwrite protection covers local `dist/`.

Historical r15-r20 test binaries predate the commit-before-build rule. Their
final source was recovered, but those individual builds are not reconstructed,
retagged or overwritten. r21 was reserved by the previous source change; this
reorganization advances both packages to r22.

After signing, run the lifecycle suite against `dist/` as well. Installation,
manual LuCI upload order, migration and recovery are documented in
[INSTALL.md](INSTALL.md). Do not install these packages on the Flint2 as part
of this work.

## Official references reviewed

Reviewed against OpenWrt 25.12 and current project guidance on 2026-08-26:

- [OpenWrt package policies](https://openwrt.org/docs/guide-developer/package-policies)
- [Creating packages](https://openwrt.org/docs/guide-developer/packages)
- [APK package manager](https://openwrt.org/docs/guide-user/additional-software/apk)
- [LuCI contribution guidelines](https://github.com/openwrt/luci/blob/openwrt-25.12/CONTRIBUTING.md)
- [LuCI package rules](https://github.com/openwrt/luci/blob/openwrt-25.12/luci.mk)
- [Standalone rpcd-mod-luci definition](https://github.com/openwrt/luci/blob/openwrt-25.12/libs/rpcd-mod-luci/Makefile)
- [OpenWrt APK packaging and conffiles](https://github.com/openwrt/openwrt/blob/openwrt-25.12/include/package-pack.mk)
- [LuCI modal API](https://openwrt.github.io/luci/jsapi/LuCI.ui.html#showModal)
- [LuCI pending changes API](https://openwrt.github.io/luci/jsapi/LuCI.uci.html#changes)
- [rpcd UCI savedir and snapshot paths](https://github.com/openwrt/rpcd/blob/master/include/rpcd/uci.h)
- [nftables atomic rule replacement](https://wiki.nftables.org/wiki-nftables/index.php/Atomic_rule_replacement)

Translations use the generated POT and future Weblate catalogs. No official
feed publication or Weblate project is created by this change.

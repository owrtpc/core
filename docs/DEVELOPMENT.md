# Development

## Build with the OpenWrt SDK or buildroot

Copy or symlink `luci-app-owrtpc` into an OpenWrt 25.12+ tree:

```sh
ln -s /path/to/OWRTPC/luci-app-owrtpc package/luci-app-owrtpc
make menuconfig
# Select LuCI > Applications > luci-app-owrtpc
make package/luci-app-owrtpc/compile V=s
```

OpenWrt 25.12 uses `apk`; install a locally copied package with:

```sh
apk add --allow-untrusted /tmp/luci-app-owrtpc-*.apk
```

## Signed release APKs

The release public key is tracked at `keys/owrtpc-release.pem`. The private key
must never be committed and defaults to:

```text
~/.config/owrtpc/signing/private-key.pem
```

Every distributed APK must come from a clean commit already pushed to
`origin/main`. Follow this order:

1. Update `PKG_RELEASE` for a new package; never reuse a distributed version.
2. Update the changelog and run the local checks below. For runtime changes,
   also run the Docker smoke test and relevant device tests.
3. Commit with `git commit --signoff` and push with `git push origin main`.
   Wait for CI to pass.
4. Run the signed build with the documented Docker SDK volume and builder image:

```sh
sh scripts/check-release.sh
./scripts/build-signed-apk.sh
```

The release check requires a clean working tree (including untracked files),
the main branch, and HEAD equal to the live remote main ref. It fails closed
when the remote cannot be queried; there is no bypass flag. It does not
automatically commit, push, or verify CI results.

The builder packages a snapshot exported from the verified commit, never the
live working directory. Ignored local files cannot enter the package. Existing
APK or provenance files are not overwritten. Keep `dist/` artifacts:
the overwrite check is local, so release-version uniqueness must also be
checked against previously distributed packages.

Each APK has `.sha256` and `.buildinfo` sidecars containing its checksum
and source commit/build metadata. Preserve these alongside the APK when
distributing it. The signing key stays outside Git.

The historical r15-r20 test APKs were built before their sources were committed.
Their final source state has now been committed, but individual historical
builds are not reconstructed or retrospectively tagged. Keep those APKs
unchanged. The next release number is r21.

Override the private-key location with `OWRTPC_SIGNING_KEY`. To trust OWRTPC
artifacts on a development router, copy the public key once:

```sh
scp -O keys/owrtpc-release.pem root@ROUTER:/tmp/owrtpc-release.pem
ssh root@ROUTER 'cp /tmp/owrtpc-release.pem /etc/apk/keys/owrtpc-release.pem && chmod 0644 /etc/apk/keys/owrtpc-release.pem'
```

After that, APKs produced by the signed-build script can be uploaded through
**System > Software** in LuCI without `--allow-untrusted`. Back up the private
key in a secure location; losing it requires distributing and trusting a new
public key.

After installation, open **Services > Parental Control** in LuCI.

## Local checks

The shell tests use command stubs and do not require nftables or OpenWrt:

```sh
./tests/run.sh
node tests/release.test.js
```

On a router, use:

```sh
owrtpcctl validate
owrtpcctl status
ubus call owrtpc status
logread -e owrtpc
nft list table inet owrtpc
```

## Publication path

Before proposing inclusion in the official LuCI feed, the project should add
device coverage, translations through Weblate, reproducible SDK builds,
integration tests on representative targets, and a documented upgrade path.
The package layout already follows the LuCI application convention so it can be
moved under `applications/luci-app-owrtpc` with minimal changes.

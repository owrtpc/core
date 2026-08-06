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

## Signed development APKs

The release public key is tracked at `keys/owrtpc-release.pem`. The private key
must never be committed and defaults to:

```text
~/.config/owrtpc/signing/private-key.pem
```

With the documented Docker SDK volume and builder image available, build and
individually sign the package with:

```sh
./scripts/build-signed-apk.sh
```

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

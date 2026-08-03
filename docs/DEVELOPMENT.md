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

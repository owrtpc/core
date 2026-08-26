# Docker test environment

This environment derives a local ARM64 container image from the official
OpenWrt 25.12.5 Xiaomi Mi Router AX3000T sysupgrade image. Extraction happens
inside Linux so case-sensitive module names and SquashFS device nodes are
preserved.

## Build and run

```sh
./docker/build-image.sh
docker compose -f docker/compose.yml up -d
./docker/smoke-test.sh
```

Open <http://localhost:8080/> and log in with:

- username: `root`
- password: `owrtpc`

Stop the environment with:

```sh
docker compose -f docker/compose.yml down
```

Pass a different sysupgrade image as the first build argument, provided it is
an ARM64 OpenWrt tar sysupgrade containing a SquashFS `root` member:

```sh
./docker/build-image.sh /absolute/path/to/firmware.bin
```

Set `OWRTPC_IMAGE` to change the resulting image tag and
`OWRTPC_HTTP_PORT` to change the host HTTP port.

## Scope and limitations

The container runs the firmware's real userspace, LuCI, rpcd, UCI, nft and the
OWRTPC scripts. It is useful for configuration, API, UI and policy-generation
tests. It does not emulate the MediaTek SoC, Wi-Fi radios, switch, hardware
offloading, bootloader or flash layout. Final enforcement tests still require a
router or a multi-network Linux integration setup.

The derived image is deliberately local and is not pushed by these scripts.

The smoke test has been verified against the supplied OpenWrt 25.12.5 AX3000T
image. It exercises LuCI, rpcd login, the OWRTPC ubus object, a temporary
profile, quick blocking and the resulting nftables rules.

## Real package lifecycle tests

The default image overlays both source directories for UI development; overlay
smoke tests do not prove package ownership. Build a separate untouched firmware
image and install actual temporary APKs for that:

```sh
sh scripts/build-test-apks.sh
OWRTPC_OVERLAY=none OWRTPC_IMAGE=owrtpc-openwrt-base:25.12.5 ./docker/build-image.sh
sh docker/test-packages.sh
```

The suite creates disposable containers without published ports. It checks
clean install, headless operation after removal of `luci-base`, API discovery,
restricted ACLs, and migration from `dist/luci-app-owrtpc-0.1.0_alpha1-r20.apk`.
It also upgrades the signed split r22 pair and exercises full reset, including
confirmation/permission failures, pending UCI edits and same-day restart.
It verifies that removing the UI leaves the backend PID unchanged and exercises
the same nftables policy checks as the UI smoke test. Normal APK dependency and
file ownership checks remain enabled; only temporary unsigned test APKs use
`--allow-untrusted`. The historical APK signature is verified with the stable
public key. After release signing, pass the absolute `dist/` path as the first
argument to test the release payloads too.

CI runs clean/headless tests; the actual historical binary is available only
locally. `OWRTPC_LEGACY_DIR` selects its directory. Kernel cgroup warnings from
procd are expected in Docker; API, process and nftables assertions still fail
the test if functionality breaks. No hardware forwarding, Wi-Fi or physical
router behavior is claimed by these tests.

The development UI port is bound to `127.0.0.1`, since its test password is public.
The overlay uses procd to manage OWRTPC, including reset stop/start. A full reset
restores the shipped `wan`/`wan6` defaults; Docker has no netifd, so restore
`monitored_device=eth0` in the test configuration before testing traffic again.

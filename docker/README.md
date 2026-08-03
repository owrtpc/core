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

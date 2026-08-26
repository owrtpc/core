#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Build unsigned, ephemeral APKs and test the real installer on native ARM64.
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK="$PROJECT_DIR/tmp/ci"
SDK_NAME=openwrt-sdk-25.12.5-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64
FIRMWARE=openwrt-25.12.5-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin
BASE_URL=https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic
# Check the Docker daemon, not the shell host (which can be macOS).
DOCKER_ARCH=$(docker info --format '{{.Architecture}}')
case "$DOCKER_ARCH" in
	aarch64|arm64) ;;
	*) echo 'Package lifecycle tests require a native ARM64 Docker host (Netlink is not emulated).' >&2; exit 1 ;;
esac
mkdir -p "$WORK" "$PROJECT_DIR/tmp/test-apks"
cd "$WORK"
curl --fail --location --retry 3 -o "$SDK_NAME.tar.zst" "$BASE_URL/$SDK_NAME.tar.zst"
curl --fail --location --retry 3 -o "$FIRMWARE" "$BASE_URL/$FIRMWARE"
printf '%s  %s\n' \
	ff4a38a397caa2cfe1c39e18f84ddede14878221b3593c3f2c4cfe24e3ec4c25 "$SDK_NAME.tar.zst" \
	a94ac2c7177b451a29c576970cb19ed2d669031f65aca2ded80fc71ae91b9eea "$FIRMWARE" | shasum -a 256 -c -
docker build --platform linux/amd64 -t owrtpc-ci-sdk:25.12.5 \
	-f "$PROJECT_DIR/docker/sdk.Dockerfile" "$PROJECT_DIR/docker"
# Only SDK host tools use emulation. Extract on the container's Linux filesystem
# (the SDK has case-sensitive paths), and keep unsigned outputs in ignored tmp/.
docker run --rm --platform linux/amd64 \
	-v "$PROJECT_DIR:/project:ro" -v "$PROJECT_DIR/tmp/test-apks:/output" \
	-e SDK_NAME="$SDK_NAME" owrtpc-ci-sdk:25.12.5 sh -ec '
		mkdir /work
		tar --zstd -xf "/project/tmp/ci/$SDK_NAME.tar.zst" -C /work
		cd "/work/$SDK_NAME"
		sh /project/scripts/setup-sdk.sh
		ln -s /project/owrtpc package/owrtpc
		ln -s /project/luci-app-owrtpc package/luci-app-owrtpc
		sh /project/scripts/sdk-build.sh
		for package in owrtpc luci-app-owrtpc; do
			cp bin/packages/aarch64_cortex-a53/base/"$package"-*.apk /output/
		done
	'
cd "$PROJECT_DIR"
OWRTPC_OVERLAY=none OWRTPC_IMAGE=owrtpc-openwrt-base:25.12.5 \
	./docker/build-image.sh "$WORK/$FIRMWARE"
# The historical signed r20 APK is not in Git. CI verifies clean/headless
# installs; migration from that actual distributed binary is a local release
# requirement, not replaced by an invented historical build here.
OWRTPC_PACKAGE_TEST_MODES='clean headless' sh docker/test-packages.sh
# No unsigned APK upload/publication from CI, including pull-request runs.

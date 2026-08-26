#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Linux CI only: build unsigned, ephemeral APKs and test the real installer.
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
WORK="$PROJECT_DIR/tmp/ci"
SDK_NAME=openwrt-sdk-25.12.5-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64
FIRMWARE=openwrt-25.12.5-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin
BASE_URL=https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic
mkdir -p "$WORK" "$PROJECT_DIR/tmp/test-apks"
cd "$WORK"
curl --fail --location --retry 3 -o "$SDK_NAME.tar.zst" "$BASE_URL/$SDK_NAME.tar.zst"
curl --fail --location --retry 3 -o "$FIRMWARE" "$BASE_URL/$FIRMWARE"
printf '%s  %s\n' \
	ff4a38a397caa2cfe1c39e18f84ddede14878221b3593c3f2c4cfe24e3ec4c25 "$SDK_NAME.tar.zst" \
	a94ac2c7177b451a29c576970cb19ed2d669031f65aca2ded80fc71ae91b9eea "$FIRMWARE" | sha256sum -c -
tar --zstd -xf "$SDK_NAME.tar.zst"
cd "$SDK_NAME"
sh "$PROJECT_DIR/scripts/setup-sdk.sh"
ln -s "$PROJECT_DIR/owrtpc" package/owrtpc
ln -s "$PROJECT_DIR/luci-app-owrtpc" package/luci-app-owrtpc
sh "$PROJECT_DIR/scripts/sdk-build.sh"
for package in owrtpc luci-app-owrtpc; do
	cp bin/packages/aarch64_cortex-a53/base/"$package"-*.apk "$PROJECT_DIR/tmp/test-apks/"
done
cd "$PROJECT_DIR"
OWRTPC_OVERLAY=none OWRTPC_IMAGE=owrtpc-openwrt-base:25.12.5 \
	./docker/build-image.sh "$WORK/$FIRMWARE"
# The historical signed r20 APK is not in Git. CI verifies clean/headless
# installs; migration from that actual distributed binary is a local release
# requirement, not replaced by an invented historical build here.
OWRTPC_PACKAGE_TEST_MODES='clean headless' sh docker/test-packages.sh
# No unsigned APK upload/publication from CI, including pull-request runs.

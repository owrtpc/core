#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Standard SDK dependency traversal and LuCI minification on native x86_64.
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SDK_NAME=openwrt-sdk-25.12.5-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64
mkdir -p "$PROJECT_DIR/tmp/full-sdk"
curl --fail --location --retry 3 -o "$PROJECT_DIR/tmp/full-sdk/$SDK_NAME.tar.zst" \
	"https://downloads.openwrt.org/releases/25.12.5/targets/mediatek/filogic/$SDK_NAME.tar.zst"
printf '%s  %s\n' ff4a38a397caa2cfe1c39e18f84ddede14878221b3593c3f2c4cfe24e3ec4c25 \
	"$PROJECT_DIR/tmp/full-sdk/$SDK_NAME.tar.zst" | shasum -a 256 -c -
docker build --platform linux/amd64 -t owrtpc-ci-sdk:25.12.5 \
	-f "$PROJECT_DIR/docker/sdk.Dockerfile" "$PROJECT_DIR/docker"
docker run --rm --platform linux/amd64 -v "$PROJECT_DIR:/project:ro" \
	-e SDK_NAME="$SDK_NAME" owrtpc-ci-sdk:25.12.5 sh -ec '
		mkdir /work
		tar --zstd -xf "/project/tmp/full-sdk/$SDK_NAME.tar.zst" -C /work
		cd "/work/$SDK_NAME"
		sh /project/scripts/setup-sdk.sh
		ln -s /project/owrtpc package/owrtpc
		ln -s /project/luci-app-owrtpc package/luci-app-owrtpc
		sh /project/scripts/sdk-build.sh --full
	'

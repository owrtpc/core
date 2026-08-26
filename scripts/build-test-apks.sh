#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Unpublished, unsigned test artifacts ONLY. Never use these for a release.
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUTPUT_DIR="$PROJECT_DIR/tmp/test-apks"
SDK_DIR=/build/openwrt-sdk-25.12.5-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64
mkdir -p "$OUTPUT_DIR"
BUILD_WORK=$(mktemp -d "$PROJECT_DIR/tmp/test-build.XXXXXX")
trap 'rm -rf "$BUILD_WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cp -R "$PROJECT_DIR/owrtpc" "$PROJECT_DIR/luci-app-owrtpc" "$BUILD_WORK/"
cp "$PROJECT_DIR/scripts/sdk-build.sh" "$BUILD_WORK/sdk-build.sh"
mkdir "$BUILD_WORK/output"
docker run --rm --platform linux/amd64 \
	-v "${OWRTPC_SDK_VOLUME:-owrtpc-sdk-25.12.5}:/build" \
	-v "$BUILD_WORK/owrtpc:$SDK_DIR/package/owrtpc:ro" \
	-v "$BUILD_WORK/luci-app-owrtpc:$SDK_DIR/package/luci-app-owrtpc:ro" \
	-v "$BUILD_WORK/sdk-build.sh:/sdk-build.sh:ro" \
	-v "$BUILD_WORK/output:/output" \
	"${OWRTPC_BUILDER_IMAGE:-owrtpc-sdk-builder:25.12.5}" sh -ec "
		cd '$SDK_DIR'
		sh /sdk-build.sh
		for name in owrtpc luci-app-owrtpc; do
			cp bin/packages/aarch64_cortex-a53/base/\$name-*.apk /output/
		done
	"
cp "$BUILD_WORK/output/"*.apk "$OUTPUT_DIR/"
printf '%s\n' 'UNSIGNED DEVELOPMENT ARTIFACTS - DO NOT DISTRIBUTE' > "$OUTPUT_DIR/README"

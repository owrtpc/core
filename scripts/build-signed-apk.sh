#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SDK_VOLUME=${OWRTPC_SDK_VOLUME:-owrtpc-sdk-25.12.5}
BUILDER_IMAGE=${OWRTPC_BUILDER_IMAGE:-owrtpc-sdk-builder:25.12.5}
SDK_DIR=/build/openwrt-sdk-25.12.5-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64
CONFIG_DIR=${XDG_CONFIG_HOME:-"$HOME/.config"}
SIGNING_KEY=${OWRTPC_SIGNING_KEY:-"$CONFIG_DIR/owrtpc/signing/private-key.pem"}
PUBLIC_KEY="$PROJECT_DIR/keys/owrtpc-release.pem"
OUTPUT_DIR="$PROJECT_DIR/dist"

version=$(sed -n 's/^PKG_VERSION:=//p' "$PROJECT_DIR/luci-app-owrtpc/Makefile")
release=$(sed -n 's/^PKG_RELEASE:=//p' "$PROJECT_DIR/luci-app-owrtpc/Makefile")
package="luci-app-owrtpc-${version}-r${release}.apk"

if [ ! -r "$SIGNING_KEY" ]; then
	echo "Signing key not found or unreadable: $SIGNING_KEY" >&2
	exit 1
fi
if [ ! -r "$PUBLIC_KEY" ]; then
	echo "Public key not found: $PUBLIC_KEY" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIR"

docker run --rm --platform linux/amd64 \
	-v "$SDK_VOLUME:/build" \
	-v "$PROJECT_DIR/luci-app-owrtpc:$SDK_DIR/package/luci-app-owrtpc:ro" \
	-v "$OUTPUT_DIR:/output" \
	-v "$SIGNING_KEY:/signing/private-key.pem:ro" \
	-v "$PUBLIC_KEY:/signing/owrtpc-release.pem:ro" \
	"$BUILDER_IMAGE" sh -ec "
		cd '$SDK_DIR'
		make package/luci-app-owrtpc/clean
		make package/luci-app-owrtpc/compile V=s -j1
		cp 'bin/packages/aarch64_cortex-a53/base/$package' '/tmp/$package'
		staging_dir/host/bin/apk --allow-untrusted adbsign \
			--reset-signatures --sign-key /signing/private-key.pem '/tmp/$package'
		staging_dir/host/bin/apk --keys-dir /signing verify '/tmp/$package'
		cp '/tmp/$package' '/output/$package'
	"

sha256sum "$OUTPUT_DIR/$package" 2>/dev/null || shasum -a 256 "$OUTPUT_DIR/$package"

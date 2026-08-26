#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
SOURCE_COMMIT=$(sh "$PROJECT_DIR/scripts/check-release.sh" "$PROJECT_DIR")
SDK_VOLUME=${OWRTPC_SDK_VOLUME:-owrtpc-sdk-25.12.5}
BUILDER_IMAGE=${OWRTPC_BUILDER_IMAGE:-owrtpc-sdk-builder:25.12.5}
SDK_DIR=/build/openwrt-sdk-25.12.5-mediatek-filogic_gcc-14.3.0_musl.Linux-x86_64
CONFIG_DIR=${XDG_CONFIG_HOME:-"$HOME/.config"}
SIGNING_KEY=${OWRTPC_SIGNING_KEY:-"$CONFIG_DIR/owrtpc/signing/private-key.pem"}
OUTPUT_DIR="$PROJECT_DIR/dist"

# Use only committed files, excluding ignored local files and later edits.
mkdir -p "$PROJECT_DIR/tmp"
BUILD_WORK=$(mktemp -d "$PROJECT_DIR/tmp/release.XXXXXX")
trap 'rm -rf "$BUILD_WORK"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
git -C "$PROJECT_DIR" archive --format=tar --output="$BUILD_WORK/source.tar" \
	"$SOURCE_COMMIT" owrtpc luci-app-owrtpc keys scripts/sdk-build.sh
tar -xf "$BUILD_WORK/source.tar" -C "$BUILD_WORK"
PUBLIC_KEY="$BUILD_WORK/keys/owrtpc-release.pem"

packages=''
for name in owrtpc luci-app-owrtpc; do
	version=$(sed -n 's/^PKG_VERSION:=//p' "$BUILD_WORK/$name/Makefile")
	release=$(sed -n 's/^PKG_RELEASE:=//p' "$BUILD_WORK/$name/Makefile")
	case "$version" in ''|*[!a-zA-Z0-9._+~-]*) echo 'Invalid package version' >&2; exit 1 ;; esac
	case "$release" in ''|*[!0-9]*) echo 'Invalid package release' >&2; exit 1 ;; esac
	packages="$packages $name-${version}-r${release}.apk"
done

check_overwrite() {
	for package in $packages; do
		for artifact in "$package" "$package.sha256" "$package.buildinfo"; do
			if [ -e "$OUTPUT_DIR/$artifact" ]; then
				echo "Release blocked: $artifact already exists; bump PKG_RELEASE, commit and push." >&2
				exit 1
			fi
		done
	done
}
check_overwrite

if [ ! -r "$SIGNING_KEY" ]; then
	echo "Signing key not found or unreadable: $SIGNING_KEY" >&2
	exit 1
fi
if [ ! -r "$PUBLIC_KEY" ]; then
	echo "Public key not found: $PUBLIC_KEY" >&2
	exit 1
fi

mkdir -p "$OUTPUT_DIR" "$BUILD_WORK/output"
# Prevent two concurrent builds of the same release in this checkout.
BUILD_LOCK="$OUTPUT_DIR/.release.lock"
mkdir "$BUILD_LOCK" || { echo 'Release build already in progress' >&2; exit 1; }
trap 'rmdir "$BUILD_LOCK"; rm -rf "$BUILD_WORK"' EXIT
check_overwrite

printf 'Building %s from pushed commit %s\n' "$packages" "$SOURCE_COMMIT"
docker run --rm --platform linux/amd64 \
	-v "$SDK_VOLUME:/build" \
	-v "$BUILD_WORK/owrtpc:$SDK_DIR/package/owrtpc:ro" \
	-v "$BUILD_WORK/scripts/sdk-build.sh:/sdk-build.sh:ro" \
	-v "$BUILD_WORK/luci-app-owrtpc:$SDK_DIR/package/luci-app-owrtpc:ro" \
	-v "$BUILD_WORK/output:/output" \
	-v "$SIGNING_KEY:/signing/private-key.pem:ro" \
	-v "$PUBLIC_KEY:/signing/owrtpc-release.pem:ro" \
	"$BUILDER_IMAGE" sh -ec "
		cd '$SDK_DIR'
		sh /sdk-build.sh
		for package in $packages; do
			cp \"bin/packages/aarch64_cortex-a53/base/\$package\" \"/tmp/\$package\"
			staging_dir/host/bin/apk --allow-untrusted adbsign \
				--reset-signatures --sign-key /signing/private-key.pem \"/tmp/\$package\"
			staging_dir/host/bin/apk --keys-dir /signing verify \"/tmp/\$package\"
			cp \"/tmp/\$package\" \"/output/\$package\"
		done
	"

for package in $packages; do
(
	cd "$BUILD_WORK/output"
	if command -v sha256sum >/dev/null 2>&1; then
		sha256sum "$package"
	else
		shasum -a 256 "$package"
	fi
) > "$BUILD_WORK/output/$package.sha256"

{
	printf 'source_commit=%s\n' "$SOURCE_COMMIT"
	printf 'source_ref=refs/heads/main\n'
	printf 'source_repository=https://github.com/owrtpc/core\n'
	printf 'package=%s\n' "$package"
	printf 'builder_image=%s\n' "$BUILDER_IMAGE"
	printf 'sdk_directory=%s\n' "$SDK_DIR"
	printf 'built_at_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$BUILD_WORK/output/$package.buildinfo"

done
# Publish only after both packages have been built, signed and verified.
for package in $packages; do
cp "$BUILD_WORK/output/$package.sha256" "$BUILD_WORK/output/$package.buildinfo" "$OUTPUT_DIR/"
cp "$BUILD_WORK/output/$package" "$OUTPUT_DIR/$package"
printf 'Release written to %s (with .sha256 and .buildinfo)\n' "$OUTPUT_DIR/$package"
done

#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FIRMWARE_DEFAULT="$HOME/Downloads/openwrt-25.12.5-mediatek-filogic-xiaomi_mi-router-ax3000t-squashfs-sysupgrade.bin"
FIRMWARE=${1:-$FIRMWARE_DEFAULT}
IMAGE=${OWRTPC_IMAGE:-owrtpc-openwrt:25.12.5-ax3000t}
TOOLS_IMAGE=${OWRTPC_TOOLS_IMAGE:-owrtpc-squashfs-tools:3.22}
mkdir -p "$PROJECT_DIR/tmp"
OUTPUT_DIR=$(mktemp -d "$PROJECT_DIR/tmp/docker-build.XXXXXX")
OVERLAY=${OWRTPC_OVERLAY:-both}
case "$OVERLAY" in both|none) ;; *) echo 'OWRTPC_OVERLAY must be both or none' >&2; exit 1 ;; esac

cleanup() {
	rm -rf "$OUTPUT_DIR"
}
trap cleanup EXIT INT TERM

if [ ! -f "$FIRMWARE" ]; then
	echo "Firmware not found: $FIRMWARE" >&2
	exit 1
fi

if ! tar -tf "$FIRMWARE" | grep -q '/root$'; then
	echo "The firmware does not contain a sysupgrade root image" >&2
	exit 1
fi

echo "Building SquashFS extraction tool..."
docker build --platform linux/arm64 \
	-t "$TOOLS_IMAGE" \
	-f "$PROJECT_DIR/docker/extractor.Dockerfile" \
	"$PROJECT_DIR/docker"

echo "Extracting OpenWrt and overlaying OWRTPC..."
docker run --rm --privileged --platform linux/arm64 \
	-v "$FIRMWARE:/input/firmware.bin:ro" \
	-v "$PROJECT_DIR:/project:ro" \
	-v "$OUTPUT_DIR:/output" \
	-e OWRTPC_OVERLAY="$OVERLAY" \
	"$TOOLS_IMAGE" sh -ec '
		mkdir -p /work/firmware
		tar -xf /input/firmware.bin -C /work/firmware
		root_image=$(find /work/firmware -type f -name root | head -n 1)
		[ -n "$root_image" ]
		unsquashfs -no-progress -d /work/rootfs "$root_image" >/dev/null
		mkdir -p /work/rootfs/usr/local/bin
		if [ "$OWRTPC_OVERLAY" = both ]; then
			cp -a /project/owrtpc/files/. /work/rootfs/
			mkdir -p /work/rootfs/usr/share/owrtpc/defaults
			cp /project/owrtpc/files/etc/config/owrtpc /work/rootfs/usr/share/owrtpc/defaults/owrtpc
			chmod 0755 /work/rootfs/usr/libexec/owrtpc-reset
			cp -a /project/luci-app-owrtpc/root/. /work/rootfs/
			mkdir -p /work/rootfs/www
			cp -a /project/luci-app-owrtpc/htdocs/. /work/rootfs/www/
		fi
		cp /project/docker/entrypoint.sh /work/rootfs/usr/local/bin/owrtpc-docker-entrypoint
		chmod 0755 /work/rootfs/usr/local/bin/owrtpc-docker-entrypoint
		tar --numeric-owner -cpf /output/rootfs.tar -C /work/rootfs .
	'

echo "Importing $IMAGE..."
docker import --platform linux/arm64 \
	--change 'ENTRYPOINT ["/usr/local/bin/owrtpc-docker-entrypoint"]' \
	--change 'EXPOSE 80' \
	--change 'ENV PATH=/usr/sbin:/usr/bin:/sbin:/bin' \
	"$OUTPUT_DIR/rootfs.tar" "$IMAGE" >/dev/null

echo "Created image: $IMAGE"

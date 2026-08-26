#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
PACKAGES=${1:-$PROJECT_DIR/tmp/test-apks}
LEGACY_DIR=${OWRTPC_LEGACY_DIR:-$PROJECT_DIR/dist}
for mode in ${OWRTPC_PACKAGE_TEST_MODES:-clean headless upgrade}; do
	docker run --rm --platform linux/arm64 --cap-add NET_ADMIN --cap-add NET_RAW \
		-v "$PROJECT_DIR:/project:ro" -v "$PACKAGES:/packages:ro" \
		-v "$LEGACY_DIR:/legacy:ro" \
		--entrypoint /bin/sh "${OWRTPC_BASE_IMAGE:-owrtpc-openwrt-base:25.12.5}" \
		/project/docker/package-test.sh "$mode"
done

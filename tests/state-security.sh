#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
work=$(mktemp -d /tmp/owrtpc-state-security.XXXXXX)
trap 'rm -rf "$work"' EXIT
export OWRTPC_TEST_MODE=1 OWRTPC_FUNCTIONS_LIB="$PROJECT_DIR/tests/functions.stub.sh"
. "$PROJECT_DIR/owrtpc/files/usr/sbin/owrtpcctl"
STATE_DIR="$work/state"
PERSIST_DIR="$work/persist"
mkdir "$work/victim"
printf 'untouched\n' > "$work/victim/date"
ln -s "$work/victim" "$STATE_DIR"
if ensure_state; then echo 'FAIL: symlink directory accepted'; exit 1; fi
rm "$STATE_DIR"
mkdir -m 0777 "$STATE_DIR"
if ensure_state; then echo 'FAIL: writable directory accepted'; exit 1; fi
chmod 0700 "$STATE_DIR"
ln -s "$work/victim/date" "$STATE_DIR/date"
if ensure_state; then echo 'FAIL: symlink state file accepted'; exit 1; fi
rm "$STATE_DIR/date"
ln -s "$work/victim" "$PERSIST_DIR"
if ensure_state; then echo 'FAIL: symlink persistence accepted'; exit 1; fi
rm "$PERSIST_DIR"
grep -qx untouched "$work/victim/date"
ensure_state
[ "$(cat "$STATE_DIR/date")" = "$(date +%F)" ]
echo 'PASS: unsafe directories/state links refused without touching targets'

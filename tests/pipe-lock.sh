#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
CTL_SOURCE=${OWRTPC_TEST_CTL_SOURCE:-$PROJECT_DIR/owrtpc/files/usr/sbin/owrtpcctl}
work=$(mktemp -d /tmp/owrtpc-pipe-lock.XXXXXX)
trap 'rm -rf "$work"' EXIT
# Run the actual CLI with isolated OpenWrt dependencies and a large response.
sed "s|^\. /usr/share/owrtpc/lock.sh$|. $PROJECT_DIR/owrtpc/files/usr/share/owrtpc/lock.sh|" \
    "$CTL_SOURCE" > "$work/ctl"
cat > "$work/functions.sh" <<'EOF'
config_load() { :; }
config_foreach() {
    i=0
    while [ "$i" -lt 10000 ]; do
        printf 'diagnostic fixture row %s\n' "$i"
        i=$((i + 1))
    done
}
EOF
OWRTPC_TEST_MODE=0 OWRTPC_FUNCTIONS_LIB="$work/functions.sh" \
OWRTPC_STATE_DIR="$work/state" OWRTPC_PERSIST_DIR="$work/persist" \
OWRTPC_LOCK_DIR="$work/locks" sh "$work/ctl" diagnostics 2> "$work/stderr" |
    head -n 1 > /dev/null
if [ -d "$work/locks/owrtpc-engine.lock" ]; then
    echo 'FAIL: interrupted diagnostic output left the engine locked'
    exit 1
fi
# A later CLI read must still acquire the same lock successfully.
OWRTPC_TEST_MODE=0 OWRTPC_FUNCTIONS_LIB="$work/functions.sh" \
OWRTPC_STATE_DIR="$work/state" OWRTPC_PERSIST_DIR="$work/persist" \
OWRTPC_LOCK_DIR="$work/locks" sh "$work/ctl" diagnostics > /dev/null
echo 'PASS: interrupted diagnostics release the engine lock; subsequent reads succeed'

#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

# Locks live outside the data directories: reset must never delete a lock
# held by a sampler, checkpoint or RPC request.
OWRTPC_ENGINE_LOCK=${OWRTPC_LOCK_DIR:-/var/lock}/owrtpc-engine.lock
OWRTPC_ACTION_LOCK=${OWRTPC_LOCK_DIR:-/var/lock}/owrtpc-action.lock

owrtpc_lock() {
	local attempt=0
	mkdir -p "${OWRTPC_LOCK_DIR:-/var/lock}" || return 1
	while ! mkdir "$1" 2>/dev/null; do
		attempt=$((attempt + 1))
		[ "$attempt" -lt "${2:-10}" ] || {
			echo 'OWRTPC is busy; try again after the current operation finishes.' >&2
			return 1
		}
		sleep 1
	done
}

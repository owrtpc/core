#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TEST_ROOT=$(mktemp -d /tmp/owrtpc-tests.XXXXXX)
trap 'rm -rf "$TEST_ROOT"' EXIT INT TERM

export OWRTPC_TEST_MODE=1
export OWRTPC_FUNCTIONS_LIB="$PROJECT_DIR/tests/functions.stub.sh"
export OWRTPC_STATE_DIR="$TEST_ROOT/state"
export OWRTPC_PERSIST_DIR="$TEST_ROOT/persist"

# shellcheck source=/dev/null
. "$PROJECT_DIR/luci-app-owrtpc/root/usr/sbin/owrtpcctl"

passed=0
failed=0

assert_eq() {
	expected="$1"
	actual="$2"
	label="$3"
	if [ "$expected" = "$actual" ]; then
		passed=$((passed + 1))
		printf 'ok - %s\n' "$label"
	else
		failed=$((failed + 1))
		printf 'not ok - %s (expected %s, got %s)\n' "$label" "$expected" "$actual"
	fi
}

mkdir -p "$OWRTPC_STATE_DIR" "$OWRTPC_PERSIST_DIR"
printf '%s\n' "$(date +%F)" > "$OWRTPC_STATE_DIR/date"

assert_eq 1290 "$(time_minutes 21:30)" 'HH:MM conversion'
is_bedtime 21:30 07:00 "$(time_minutes 23:00)" && bedtime_late=yes || bedtime_late=no
assert_eq yes "$bedtime_late" 'bedtime crossing midnight: late evening'
is_bedtime 21:30 07:00 "$(time_minutes 06:59)" && bedtime_early=yes || bedtime_early=no
assert_eq yes "$bedtime_early" 'bedtime crossing midnight: early morning'
is_bedtime 21:30 07:00 "$(time_minutes 12:00)" && bedtime_noon=yes || bedtime_noon=no
assert_eq no "$bedtime_noon" 'bedtime crossing midnight: daytime allowed'

COUNTERS_FILE="$TEST_ROOT/counters"
cat > "$COUNTERS_FILE" <<'COUNTERS'
AA:BB:CC:DD:EE:01	4096
AA:BB:CC:DD:EE:02	2048
AA:BB:CC:DD:EE:03	100
COUNTERS
SAMPLE_THRESHOLD=1024
SAMPLE_ELAPSED=60
sample_device AA:BB:CC:DD:EE:01 children
sample_device AA:BB:CC:DD:EE:02 children
sample_device AA:BB:CC:DD:EE:03 children
assert_eq 120 "$(get_used children)" 'two active devices add two device-minutes to one profile'
assert_eq 0 "$(get_used another_profile)" 'other profiles remain independent'

config_get_bool() {
	variable="$1"; section="$2"; option="$3"; default="$4"
	case "$option" in enabled) value=1 ;; blocked) value=0 ;; *) value="$default" ;; esac
	eval "$variable=\$value"
}
config_get() {
	variable="$1"; section="$2"; option="$3"; default="$4"
	case "$option" in
		daily_minutes) value=2 ;;
		bedtime_start|bedtime_end) value='' ;;
		*) value="$default" ;;
	esac
	eval "$variable=\$value"
}
assert_eq quota "$(profile_reason children)" 'profile blocks when cumulative quota is exhausted'

set_used children 180
config_get() {
	variable="$1"; section="$2"; option="$3"; default="$4"
	case "$option" in
		weekday_daily_minutes) value=2 ;;
		weekend_daily_minutes) value=4 ;;
		weekday_bedtime_start) value='21:30' ;;
		weekday_bedtime_end) value='07:00' ;;
		weekend_bedtime_start) value='23:00' ;;
		weekend_bedtime_end) value='09:00' ;;
		daily_minutes) value=0 ;;
		bedtime_start|bedtime_end) value='' ;;
		*) value="$default" ;;
	esac
	eval "$variable=\$value"
}
export OWRTPC_NOW_HHMM=22:00
export OWRTPC_DAY_OF_WEEK=1
assert_eq weekday "$(current_schedule)" 'Monday selects the weekday schedule'
assert_eq bedtime "$(profile_reason children)" 'weekday bedtime uses weekday hours'
export OWRTPC_DAY_OF_WEEK=6
assert_eq weekend "$(current_schedule)" 'Saturday selects the weekend schedule'
assert_eq none "$(profile_reason children)" 'weekend uses its own quota and bedtime'
export OWRTPC_NOW_HHMM=23:30
assert_eq bedtime "$(profile_reason children)" 'weekend bedtime uses weekend hours'
unset OWRTPC_NOW_HHMM OWRTPC_DAY_OF_WEEK
set_used children 120

config_get_bool() {
	variable="$1"; section="$2"; option="$3"; default="$4"
	case "$option:$section" in
		enabled:*) value=1 ;;
		blocked:p2) value=1 ;;
		blocked:*) value=0 ;;
		*) value="$default" ;;
	esac
	eval "$variable=\$value"
}
config_get() {
	variable="$1"; section="$2"; option="$3"; default="$4"
	case "$option" in
		daily_minutes) value=0 ;;
		bedtime_start|bedtime_end) value='' ;;
		*) value="$default" ;;
	esac
	eval "$variable=\$value"
}
config_list_foreach() {
	section="$1"; option="$2"; callback="$3"; shift 3
	case "$section:$option" in
		p1:device) list='AA:BB:CC:DD:EE:01 AA:BB:CC:DD:EE:02' ;;
		p2:device) list='AA:BB:CC:DD:EE:01 AA:BB:CC:DD:EE:03' ;;
		*) list='' ;;
	esac
	for item in $list; do "$callback" "$item" "$@"; done
}
APPLY_SEEN="$TEST_ROOT/apply-seen"
APPLY_BLOCKS="$TEST_ROOT/apply-blocks"
APPLY_COUNTERS="$TEST_ROOT/apply-counters"
APPLY_OUTPUT_DEVICES="$TEST_ROOT/apply-output-devices"
: > "$APPLY_SEEN"
: > "$APPLY_BLOCKS"
: > "$APPLY_COUNTERS"
printf 'wan0\n' > "$APPLY_OUTPUT_DEVICES"
apply_profile p1
apply_profile p2
assert_eq 2 "$(grep -c 'counter comment' "$APPLY_COUNTERS")" 'allowed devices receive per-device counters'
assert_eq 1 "$(grep -c 'owrtpc-duplicate:AA:BB:CC:DD:EE:01' "$APPLY_BLOCKS")" 'duplicate assignment fails closed'
assert_eq 1 "$(grep -c 'owrtpc-block:manual:AA:BB:CC:DD:EE:03' "$APPLY_BLOCKS")" 'manual block produces a WAN drop rule'
wan_rule_count=$(grep -h 'oifname "wan0"' "$APPLY_BLOCKS" "$APPLY_COUNTERS" | wc -l | tr -d ' ')
assert_eq 4 "$wan_rule_count" 'rules are limited to the monitored Internet device'

printf '%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]

if command -v node >/dev/null 2>&1; then
	node "$PROJECT_DIR/tests/devices.test.js"
else
	printf 'skip - device autocomplete tests require Node.js\n'
fi

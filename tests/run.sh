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
. "$PROJECT_DIR/owrtpc/files/usr/sbin/owrtpcctl"

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
write_counters() {
	printf '%s\t%s\n' 'AA:BB:CC:DD:EE:01' "$1" > "$COUNTERS_FILE"
}
SAMPLE_THRESHOLD=131072
SAMPLE_PROFILE_THRESHOLD="$SAMPLE_THRESHOLD"
SAMPLE_ELAPSED=60
SAMPLE_NOW=1000
ACTIVITY_CONFIRM_WINDOW=300
ACTIVITY_IDLE_TIMEOUT=180

write_counters 262144
sample_device AA:BB:CC:DD:EE:01 children
assert_eq 0 "$(get_used children)" 'the first traffic burst is only a session candidate'
SAMPLE_NOW=1060
sample_device AA:BB:CC:DD:EE:01 children
assert_eq 120 "$(get_used children)" 'a second burst confirms and retroactively counts the session'
assert_eq 120 "$(get_device_used AA:BB:CC:DD:EE:01)" 'confirmed session is attributed to its device'

write_counters 0
SAMPLE_NOW=1120
sample_device AA:BB:CC:DD:EE:01 children
assert_eq 120 "$(get_used children)" 'a buffering gap remains provisional'
write_counters 262144
SAMPLE_NOW=1180
sample_device AA:BB:CC:DD:EE:01 children
assert_eq 240 "$(get_used children)" 'traffic resuming inside the grace period confirms the buffering gap'
assert_eq 240 "$(get_device_used AA:BB:CC:DD:EE:01)" 'resumed buffering gap is attributed to its device'
DIAGNOSTICS_PROFILE_NAME=Children
diagnostics_row=$(diagnostics_device AA:BB:CC:DD:EE:01 children)
assert_eq 240 "$(printf '%s\n' "$diagnostics_row" | cut -f4)" 'diagnostics output exposes attributed device time'
assert_eq active "$(printf '%s\n' "$diagnostics_row" | cut -f5)" 'diagnostics output exposes the activity state'
assert_eq 262144 "$(printf '%s\n' "$diagnostics_row" | cut -f8)" 'diagnostics output exposes the latest sampled bytes'
add_profile_usage children AA:BB:CC:DD:EE:02 60
assert_eq 300 "$(get_used children)" 'a second device contributes to the cumulative profile total'
assert_eq 60 "$(get_device_used AA:BB:CC:DD:EE:02)" 'the second device keeps separate diagnostic attribution'
set_used children 240
set_device_used AA:BB:CC:DD:EE:02 0

write_counters 0
SAMPLE_NOW=1240
sample_device AA:BB:CC:DD:EE:01 children
SAMPLE_NOW=1300
sample_device AA:BB:CC:DD:EE:01 children
SAMPLE_NOW=1360
sample_device AA:BB:CC:DD:EE:01 children
assert_eq 240 "$(get_used children)" 'the silent tail is discarded when the active session expires'
assert_eq 0 "$(activity_read AA:BB:CC:DD:EE:01 active)" 'the device returns to idle after the grace period'

write_counters 262144
SAMPLE_NOW=1420
sample_device AA:BB:CC:DD:EE:01 isolated_profile
write_counters 0
SAMPLE_NOW=1720
sample_device AA:BB:CC:DD:EE:01 isolated_profile
assert_eq 0 "$(get_used isolated_profile)" 'an isolated heavy background burst never consumes time'

clear_device_activity AA:BB:CC:DD:EE:01
write_counters 262144
TEST_DAILY_MINUTES=0
config_get_bool() {
	variable="$1"; option="$3"
	case "$option" in
		enabled) value=1 ;;
		blocked) value=0 ;;
		*) value=0 ;;
	esac
	eval "$variable=\$value"
}
config_get() {
	variable="$1"; option="$3"; default="$4"
	case "$option" in
		weekday_daily_minutes|weekend_daily_minutes|daily_minutes) value="$TEST_DAILY_MINUTES" ;;
		bedtime_start|bedtime_end|weekday_bedtime_start|weekday_bedtime_end|weekend_bedtime_start|weekend_bedtime_end) value='' ;;
		activity_threshold_bytes) value="$default" ;;
		*) value="$default" ;;
	esac
	eval "$variable=\$value"
}
config_list_foreach() {
	section="$1"; option="$2"; callback="$3"; extra="${4:-}"
	[ "$option" = 'device' ] && "$callback" AA:BB:CC:DD:EE:01 "$extra"
}
SAMPLE_NOW=2000
sample_profile unlimited_profile
assert_eq 0 "$(activity_read AA:BB:CC:DD:EE:01 candidate_started)" 'unlimited profiles skip session calculations entirely'
TEST_DAILY_MINUTES=120
sample_profile limited_profile
assert_eq 2000 "$(activity_read AA:BB:CC:DD:EE:01 candidate_started)" 'limited profiles enable automatic session detection'
clear_device_activity AA:BB:CC:DD:EE:01
config_get() { :; }
config_get_bool() { :; }
config_list_foreach() { :; }

config_get_bool() {
	variable="$1"; section="$2"; option="$3"; default="$4"
	case "$option" in enabled) value="${TEST_PROFILE_ENABLED:-1}" ;; blocked) value=0 ;; *) value="$default" ;; esac
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
		mon_thu_daily_minutes) value=2 ;;
		fri_sun_daily_minutes) value=4 ;;
		sun_thu_bedtime_start) value='21:30' ;;
		sun_thu_bedtime_end) value='07:00' ;;
		fri_sat_bedtime_start) value='23:00' ;;
		fri_sat_bedtime_end) value='09:00' ;;
		daily_minutes) value=0 ;;
		bedtime_start|bedtime_end) value='' ;;
		*) value="$default" ;;
	esac
	eval "$variable=\$value"
}

export OWRTPC_NOW_HHMM=12:00
export OWRTPC_DAY_OF_WEEK=1
assert_eq mon_thu "$(current_allowance_period)" 'Monday selects the Monday-Thursday allowance'
export OWRTPC_DAY_OF_WEEK=5
assert_eq fri_sun "$(current_allowance_period)" 'Friday selects the Friday-Sunday allowance'
assert_eq none "$(profile_reason children)" 'Friday uses the larger Friday-Sunday allowance'
export OWRTPC_DAY_OF_WEEK=4
assert_eq quota "$(profile_reason children)" 'Thursday uses the Monday-Thursday allowance'

export OWRTPC_NOW_HHMM=08:00
export OWRTPC_DAY_OF_WEEK=5
profile_bedtime_active children && bedtime_friday_morning=yes || bedtime_friday_morning=no
assert_eq no "$bedtime_friday_morning" 'Friday morning does not use the upcoming Friday-night hours'
export OWRTPC_DAY_OF_WEEK=6
profile_bedtime_active children && bedtime_saturday_morning=yes || bedtime_saturday_morning=no
assert_eq yes "$bedtime_saturday_morning" 'Saturday morning continues the Friday-night bedtime'
assert_eq fri_sat "$(profile_bedtime_period children)" 'Saturday morning reports the Friday-Saturday bedtime group'
export OWRTPC_DAY_OF_WEEK=7
profile_bedtime_active children && bedtime_sunday_morning=yes || bedtime_sunday_morning=no
assert_eq yes "$bedtime_sunday_morning" 'Sunday morning continues the Saturday-night bedtime'
status_row=$(status_profile children)
assert_eq fri_sun "$(printf '%s\n' "$status_row" | cut -f11)" 'status exposes the independent allowance period'
assert_eq fri_sat "$(printf '%s\n' "$status_row" | cut -f12)" 'status exposes the overnight bedtime period'
export OWRTPC_DAY_OF_WEEK=1
profile_bedtime_active children && bedtime_monday_morning=yes || bedtime_monday_morning=no
assert_eq no "$bedtime_monday_morning" 'Monday morning ends with the Sunday-night school schedule'

export OWRTPC_NOW_HHMM=22:00
export OWRTPC_DAY_OF_WEEK=7
assert_eq sun_thu "$(profile_bedtime_period children)" 'Sunday evening selects the Sunday-Thursday bedtime group'
assert_eq bedtime "$(profile_reason children)" 'Sunday evening uses school-night bedtime hours'
export OWRTPC_DAY_OF_WEEK=5
assert_eq none "$(profile_reason children)" 'Friday evening stays allowed until the later bedtime'

export OWRTPC_DAY_OF_WEEK=1
set_bonus children 3600
set_all_day children
TEST_PROFILE_ENABLED=0
assert_eq disabled "$(profile_reason children)" 'a disabled profile bypasses bedtime'
assert_eq 3600 "$(get_bonus children)" 'disabled profiles retain unused extra time'
assert_eq 1 "$(get_all_day children)" 'disabled profiles retain All Day state'
TEST_PROFILE_ENABLED=1
assert_eq bedtime "$(profile_reason children)" 'Monday bedtime uses Sunday-Thursday hours'
assert_eq 0 "$(get_bonus children)" 'bedtime discards extra time after re-enabling'
assert_eq 0 "$(get_all_day children)" 'bedtime ends All Day after re-enabling'
export OWRTPC_DAY_OF_WEEK=6
assert_eq weekend "$(current_schedule)" 'Saturday keeps the legacy weekend allowance label'
assert_eq none "$(profile_reason children)" 'Saturday uses its own quota and later bedtime'
export OWRTPC_NOW_HHMM=23:30
set_bonus children 3600
set_all_day children
checkpoint_state
assert_eq bedtime "$(profile_reason children)" 'weekend bedtime keeps priority over extra time'
assert_eq 0 "$(get_bonus children)" 'bedtime discards unused extra time'
assert_eq 0 "$(get_all_day children)" 'bedtime ends All Day mode'
restore_state
assert_eq 0 "$(get_bonus children)" 'discarded bedtime credit cannot return after restart'
assert_eq 0 "$(get_all_day children)" 'discarded All Day mode cannot return after restart'

export OWRTPC_NOW_HHMM=12:00
export OWRTPC_DAY_OF_WEEK=1
set_used children 180
set_bonus children 3600
assert_eq none "$(profile_reason children)" 'extra time reopens a profile with exhausted base allowance'
set_used children 3720
assert_eq quota "$(profile_reason children)" 'profile blocks after base allowance and extra time are exhausted'
set_all_day children
assert_eq none "$(profile_reason children)" 'All Day overrides an exhausted quota'
replace_time_credit children 14400
replace_time_credit children 3600
assert_eq 3600 "$(get_bonus children)" 'the latest numeric quick action replaces the previous credit'
assert_eq 0 "$(get_all_day children)" 'a numeric quick action disables All Day'
replace_time_credit children all-day
assert_eq 0 "$(get_bonus children)" 'All Day replaces a numeric credit'
assert_eq 1 "$(get_all_day children)" 'All Day is enabled by the replacement action'
clear_all_day children

set_used children 180
set_bonus children 14400
checkpoint_state
clear_bonus children
set_device_used AA:BB:CC:DD:EE:01 0
restore_state
assert_eq 14400 "$(get_bonus children)" 'extra time survives a same-day service restart'
assert_eq 240 "$(get_device_used AA:BB:CC:DD:EE:01)" 'per-device diagnostic usage survives a same-day service restart'
set_all_day children
checkpoint_state
clear_all_day children
restore_state
assert_eq 1 "$(get_all_day children)" 'All Day survives a same-day service restart'
printf '1900-01-01\n' > "$OWRTPC_STATE_DIR/date"
ensure_state
assert_eq 0 "$(get_bonus children)" 'extra time never carries into the next day'
assert_eq 0 "$(get_all_day children)" 'All Day never carries into the next day'
assert_eq 0 "$(get_device_used AA:BB:CC:DD:EE:01)" 'per-device diagnostic usage resets on the next day'
unset OWRTPC_NOW_HHMM OWRTPC_DAY_OF_WEEK
set_used children 120

config_get_bool() {
	variable="$1"; section="$2"; option="$3"; default="$4"
	case "$option:$section" in
		enabled:p0) value=0 ;;
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
		p0:device) list='AA:BB:CC:DD:EE:01' ;;
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
apply_profile p0
apply_profile p1
apply_profile p2
assert_eq 2 "$(grep -c 'counter comment' "$APPLY_COUNTERS")" 'allowed devices receive per-device counters'
assert_eq 1 "$(grep -c 'owrtpc-device:AA:BB:CC:DD:EE:01' "$APPLY_COUNTERS")" 'disabled profiles do not reserve devices or create rules'
assert_eq 1 "$(grep -c 'owrtpc-duplicate:AA:BB:CC:DD:EE:01' "$APPLY_BLOCKS")" 'duplicate assignment fails closed'
assert_eq 1 "$(grep -c 'owrtpc-block:manual:AA:BB:CC:DD:EE:03' "$APPLY_BLOCKS")" 'manual block produces a WAN drop rule'
wan_rule_count=$(grep -h 'oifname "wan0"' "$APPLY_BLOCKS" "$APPLY_COUNTERS" | wc -l | tr -d ' ')
assert_eq 4 "$wan_rule_count" 'rules are limited to the monitored Internet device'

printf '%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ]

if command -v node >/dev/null 2>&1; then
	node "$PROJECT_DIR/tests/devices.test.js"
	node "$PROJECT_DIR/tests/reset.test.js"
else
	printf 'skip - device autocomplete tests require Node.js\n'
fi

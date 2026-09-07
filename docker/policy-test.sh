#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
	cleanup_profile() {
		uci -q delete owrtpc.docker_test || true
		[ -z "${created_profile:-}" ] || uci -q delete "owrtpc.$created_profile" || true
		uci commit owrtpc
		ubus -s /var/run/ubus/ubus.sock call owrtpc refresh >/dev/null 2>&1 || true
		rm -f /tmp/owrtpc/profile-docker_test.used /tmp/owrtpc/profile-docker_test.bonus /tmp/owrtpc/profile-docker_test.all_day
		rm -f /etc/owrtpc/state/profile-docker_test.used /etc/owrtpc/state/profile-docker_test.bonus /etc/owrtpc/state/profile-docker_test.all_day
	}
	trap cleanup_profile EXIT INT TERM
	uci -q delete owrtpc.docker_test || true
	uci set owrtpc.docker_test=profile
	uci set owrtpc.docker_test.name="Docker Test"
	uci set owrtpc.docker_test.enabled=1
	uci set owrtpc.docker_test.blocked=0
	uci set owrtpc.docker_test.daily_minutes=60
	uci add_list owrtpc.docker_test.device=02:42:AC:11:00:02
	uci commit owrtpc
	refresh=$(ubus -s /var/run/ubus/ubus.sock call owrtpc refresh)
	printf "%s\n" "$refresh" | grep -q "\"success\": true"
	capabilities=$(ubus -s /var/run/ubus/ubus.sock call owrtpc capabilities)
	printf "%s\n" "$capabilities" | grep -q '"api": "owrtpc-mobile"'
	printf "%s\n" "$capabilities" | grep -q '"major": 1'
	status=$(ubus -s /var/run/ubus/ubus.sock call owrtpc status)
	printf "%s\n" "$status" | grep -q "\"section\": \"docker_test\""
	snapshot=$(ubus -s /var/run/ubus/ubus.sock call owrtpc edit_snapshot)
	revision=$(printf '%s\n' "$snapshot" | jsonfilter -e '@.revision')
	[ "${#revision}" -eq 64 ]
	printf '%s\n' "$snapshot" | grep -q '"section": "docker_test"'
	apply=$(ubus -s /var/run/ubus/ubus.sock call owrtpc profile_apply "{\"expected_revision\":\"$revision\",\"section\":\"docker_test\",\"name\":\"Edited Docker Test\",\"enabled\":true,\"mon_thu_daily_minutes\":90,\"fri_sun_daily_minutes\":60,\"sun_thu_bedtime_start\":\"21:30\",\"sun_thu_bedtime_end\":\"07:00\",\"fri_sat_bedtime_start\":\"\",\"fri_sat_bedtime_end\":\"\",\"activity_threshold_bytes\":32768,\"devices\":[\"02:42:ac:11:00:02\"]}")
	printf '%s\n' "$apply" | grep -q '"success": true'
	[ "$(uci -q get owrtpc.docker_test.name)" = 'Edited Docker Test' ]
	[ "$(uci -q get owrtpc.docker_test.mon_thu_daily_minutes)" = 90 ]
	[ "$(uci -q get owrtpc.docker_test.fri_sun_daily_minutes)" = 60 ]
	[ "$(uci -q get owrtpc.docker_test.device)" = '02:42:AC:11:00:02' ]
	conflict=$(ubus -s /var/run/ubus/ubus.sock call owrtpc profile_apply "{\"expected_revision\":\"$revision\",\"section\":\"docker_test\",\"name\":\"Stale edit\",\"enabled\":true,\"mon_thu_daily_minutes\":30,\"fri_sun_daily_minutes\":30,\"sun_thu_bedtime_start\":\"\",\"sun_thu_bedtime_end\":\"\",\"fri_sat_bedtime_start\":\"\",\"fri_sat_bedtime_end\":\"\",\"activity_threshold_bytes\":0,\"devices\":[]}")
	printf '%s\n' "$conflict" | grep -q '"code": "conflicting_edit"'
	[ "$(uci -q get owrtpc.docker_test.name)" = 'Edited Docker Test' ]
	current_snapshot=$(ubus -s /var/run/ubus/ubus.sock call owrtpc edit_snapshot)
	current_revision=$(printf '%s\n' "$current_snapshot" | jsonfilter -e '@.revision')
	assigned=$(ubus -s /var/run/ubus/ubus.sock call owrtpc profile_create "{\"expected_revision\":\"$current_revision\",\"name\":\"Conflicting profile\",\"enabled\":true,\"mon_thu_daily_minutes\":30,\"fri_sun_daily_minutes\":30,\"sun_thu_bedtime_start\":\"\",\"sun_thu_bedtime_end\":\"\",\"fri_sat_bedtime_start\":\"\",\"fri_sat_bedtime_end\":\"\",\"activity_threshold_bytes\":0,\"devices\":[\"02:42:AC:11:00:02\"]}")
	printf '%s\n' "$assigned" | grep -q '"code": "validation_failed"'
	created=$(ubus -s /var/run/ubus/ubus.sock call owrtpc profile_create "{\"expected_revision\":\"$current_revision\",\"name\":\"Created Docker Test\",\"enabled\":true,\"mon_thu_daily_minutes\":45,\"fri_sun_daily_minutes\":90,\"sun_thu_bedtime_start\":\"20:30\",\"sun_thu_bedtime_end\":\"07:30\",\"fri_sat_bedtime_start\":\"\",\"fri_sat_bedtime_end\":\"\",\"activity_threshold_bytes\":0,\"devices\":[\"02:42:AC:11:00:03\"]}")
	printf '%s\n' "$created" | grep -q '"success": true'
	created_profile=$(printf '%s\n' "$created" | jsonfilter -e '@.section')
	[ "$(uci -q get "owrtpc.$created_profile")" = profile ]
	[ "$(uci -q get "owrtpc.$created_profile.name")" = 'Created Docker Test' ]
	[ "$(uci -q get "owrtpc.$created_profile.device")" = '02:42:AC:11:00:03' ]
	created_status=$(ubus -s /var/run/ubus/ubus.sock call owrtpc status)
	printf '%s\n' "$created_status" | grep -q '"name": "Created Docker Test"'
	stale_create=$(ubus -s /var/run/ubus/ubus.sock call owrtpc profile_create "{\"expected_revision\":\"$current_revision\",\"name\":\"Stale create\",\"enabled\":true,\"mon_thu_daily_minutes\":0,\"fri_sun_daily_minutes\":0,\"sun_thu_bedtime_start\":\"\",\"sun_thu_bedtime_end\":\"\",\"fri_sat_bedtime_start\":\"\",\"fri_sat_bedtime_end\":\"\",\"activity_threshold_bytes\":0,\"devices\":[]}")
	printf '%s\n' "$stale_create" | grep -q '"code": "conflicting_edit"'
	sh /project/docker/profile-order-test.sh
	sh /project/docker/profile-delete-test.sh "$created_profile"
	# Keep quick-action assertions independent of the container wall clock.
	uci set owrtpc.docker_test.mon_thu_daily_minutes=60
	uci set owrtpc.docker_test.fri_sun_daily_minutes=60
	uci -q delete owrtpc.docker_test.sun_thu_bedtime_start || true
	uci -q delete owrtpc.docker_test.sun_thu_bedtime_end || true
	uci commit owrtpc
	refresh=$(ubus -s /var/run/ubus/ubus.sock call owrtpc refresh)
	printf "%s\n" "$refresh" | grep -q '"success": true'
	diagnostics=$(/usr/sbin/owrtpcctl diagnostics)
	printf "%s\n" "$diagnostics" | grep -q "used_seconds.*activity_state.*last_bytes"
	printf "%s\n" "$diagnostics" | grep -q "docker_test.*02:42:AC:11:00:02"
	# Quick time actions grant the selected remaining time after exhaustion.
	printf '3600\n' > /tmp/owrtpc/profile-docker_test.used
	bonus=$(ubus -s /var/run/ubus/ubus.sock call owrtpc add_time "{\"profile\":\"docker_test\",\"minutes\":240}")
	printf "%s\n" "$bonus" | grep -q "\"added_seconds\": 14400"
	bonus=$(ubus -s /var/run/ubus/ubus.sock call owrtpc add_time "{\"profile\":\"docker_test\",\"minutes\":60}")
	printf "%s\n" "$bonus" | grep -q "\"added_seconds\": 3600"
	status=$(ubus -s /var/run/ubus/ubus.sock call owrtpc status)
	printf "%s\n" "$status" | grep -q "\"bonus_seconds\": 3600"
	printf "%s\n" "$status" | grep -q "\"limit_seconds\": 7200"
	all_day=$(ubus -s /var/run/ubus/ubus.sock call owrtpc add_time "{\"profile\":\"docker_test\",\"minutes\":\"all-day\"}")
	printf "%s\n" "$all_day" | grep -q "\"all_day\": true"
	status=$(ubus -s /var/run/ubus/ubus.sock call owrtpc status)
	printf "%s\n" "$status" | grep -q "\"all_day\": true"
	printf "%s\n" "$status" | grep -q "\"limit_seconds\": 0"
	bonus=$(ubus -s /var/run/ubus/ubus.sock call owrtpc add_time "{\"profile\":\"docker_test\",\"minutes\":60}")
	printf "%s\n" "$bonus" | grep -q "\"added_seconds\": 3600"
	status=$(ubus -s /var/run/ubus/ubus.sock call owrtpc status)
	printf "%s\n" "$status" | grep -q "\"all_day\": false"
	printf "%s\n" "$status" | grep -q "\"bonus_seconds\": 3600"
	printf "%s\n" "$status" | grep -q "\"limit_seconds\": 7200"
	rules=$(nft list table inet owrtpc)
	case "$rules" in *owrtpc-device:02:42:AC:11:00:02*) ;; *) exit 1 ;; esac
	toggle=$(ubus -s /var/run/ubus/ubus.sock call owrtpc set_block "{\"profile\":\"docker_test\",\"blocked\":true}")
	printf "%s\n" "$toggle" | grep -q "\"success\": true"
	rules=$(nft list table inet owrtpc)
	case "$rules" in *owrtpc-block:manual:02:42:AC:11:00:02*) ;; *) exit 1 ;; esac
	# A failed atomic refresh must retain the previous installed policy.
	nft -s list table inet owrtpc > /tmp/owrtpc-policy-before
	cat > /tmp/owrtpc-failing-nft <<'EOF'
#!/bin/sh
if [ "$1" != -f ]; then exec /usr/sbin/nft "$@"; fi
cp "$2" /tmp/owrtpc-invalid-rules
printf 'invalid nftables directive\n' >> /tmp/owrtpc-invalid-rules
exec /usr/sbin/nft -f /tmp/owrtpc-invalid-rules
EOF
	chmod 0755 /tmp/owrtpc-failing-nft
	if OWRTPC_NFT_BIN=/tmp/owrtpc-failing-nft owrtpcctl apply; then
		echo 'FAIL: invalid policy was accepted' >&2; exit 1
	fi
	nft -s list table inet owrtpc > /tmp/owrtpc-policy-after
	cmp /tmp/owrtpc-policy-before /tmp/owrtpc-policy-after
	rm -f /tmp/owrtpc-failing-nft /tmp/owrtpc-invalid-rules /tmp/owrtpc-policy-before /tmp/owrtpc-policy-after
	uci set owrtpc.docker_test.bedtime_start=00:00
	uci set owrtpc.docker_test.bedtime_end=23:59
	uci commit owrtpc
	toggle=$(ubus -s /var/run/ubus/ubus.sock call owrtpc set_enabled "{\"profile\":\"docker_test\",\"enabled\":false}")
	printf "%s\n" "$toggle" | grep -q "\"enabled\": false"
	uci -q get owrtpc.docker_test.enabled | grep -q "^0$"
	rules=$(nft list table inet owrtpc)
	case "$rules" in *02:42:AC:11:00:02*) exit 1 ;; esac
	uci -q delete owrtpc.docker_test.bedtime_start
	uci -q delete owrtpc.docker_test.bedtime_end
	uci commit owrtpc
	toggle=$(ubus -s /var/run/ubus/ubus.sock call owrtpc set_enabled "{\"profile\":\"docker_test\",\"enabled\":true}")
	printf "%s\n" "$toggle" | grep -q "\"enabled\": true"
	uci -q get owrtpc.docker_test.enabled | grep -q "^1$"
	rules=$(nft list table inet owrtpc)
	case "$rules" in *owrtpc-block:manual:02:42:AC:11:00:02*) ;; *) exit 1 ;; esac

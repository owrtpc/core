#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
	cleanup_profile() {
		uci -q delete owrtpc.docker_test || true
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
	status=$(ubus -s /var/run/ubus/ubus.sock call owrtpc status)
	printf "%s\n" "$status" | grep -q "\"section\": \"docker_test\""
	diagnostics=$(/usr/sbin/owrtpcctl diagnostics)
	printf "%s\n" "$diagnostics" | grep -q "used_seconds.*activity_state.*last_bytes"
	printf "%s\n" "$diagnostics" | grep -q "docker_test.*02:42:AC:11:00:02"
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

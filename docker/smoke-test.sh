#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

PROJECT_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
COMPOSE="docker compose -f $PROJECT_DIR/docker/compose.yml"
HTTP_PORT=${OWRTPC_HTTP_PORT:-8080}

echo 'Checking LuCI HTTP endpoint...'
curl -sS "http://127.0.0.1:$HTTP_PORT/cgi-bin/luci/" | grep -q '<title>'

echo 'Checking rpcd login...'
login_response=$(curl -fsS \
	-H 'Content-Type: application/json' \
	-d '{"jsonrpc":"2.0","id":1,"method":"call","params":["00000000000000000000000000000000","session","login",{"username":"root","password":"owrtpc"}]}' \
	"http://127.0.0.1:$HTTP_PORT/ubus")
printf '%s' "$login_response" | grep -q 'ubus_rpc_session'

echo 'Checking OWRTPC configuration and policy engine...'
$COMPOSE exec -T router /usr/sbin/owrtpcctl validate | grep -q '^OK$'
$COMPOSE exec -T router uci -q get owrtpc.main.activity_threshold_bytes | grep -q '^131072$'
$COMPOSE exec -T router uci -q get owrtpc.main.activity_confirm_window | grep -q '^300$'
$COMPOSE exec -T router uci -q get owrtpc.main.activity_idle_timeout | grep -q '^180$'
$COMPOSE exec -T router uci -q get owrtpc.main.monitored_device | grep -q '^eth0$'
$COMPOSE exec -T router nft list table inet owrtpc >/dev/null
$COMPOSE exec -T router ubus -s /var/run/ubus/ubus.sock list owrtpc | grep -q '^owrtpc$'

echo 'Checking profile lifecycle and nftables reconciliation...'
$COMPOSE exec -T router sh -ec '
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
'

echo 'Docker smoke test passed.'

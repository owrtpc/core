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
$COMPOSE exec -T router uci -q get owrtpc.main.monitored_device | grep -q '^eth0$'
$COMPOSE exec -T router nft list table inet owrtpc >/dev/null
$COMPOSE exec -T router ubus -s /var/run/ubus/ubus.sock list owrtpc | grep -q '^owrtpc$'

echo 'Checking profile lifecycle and nftables reconciliation...'
$COMPOSE exec -T router sh -ec '
	cleanup_profile() {
		uci -q delete owrtpc.docker_test || true
		uci commit owrtpc
		ubus -s /var/run/ubus/ubus.sock call owrtpc refresh >/dev/null 2>&1 || true
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
	rules=$(nft list table inet owrtpc)
	case "$rules" in *owrtpc-device:02:42:AC:11:00:02*) ;; *) exit 1 ;; esac
	toggle=$(ubus -s /var/run/ubus/ubus.sock call owrtpc set_block "{\"profile\":\"docker_test\",\"blocked\":true}")
	printf "%s\n" "$toggle" | grep -q "\"success\": true"
	rules=$(nft list table inet owrtpc)
	case "$rules" in *owrtpc-block:manual:02:42:AC:11:00:02*) ;; *) exit 1 ;; esac
'

echo 'Docker smoke test passed.'

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
$COMPOSE exec -T router sh -s < "$PROJECT_DIR/docker/policy-test.sh"

echo 'Docker smoke test passed.'

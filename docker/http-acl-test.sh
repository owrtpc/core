#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -eu
[ -f /.dockerenv ] || exit 1
reader=$1
/usr/sbin/uhttpd -f -h /www -u /ubus -p 127.0.0.1:18080 &
server=$!
trap 'kill "$server"; wait "$server" || true' EXIT
sleep 1
post() {
    wget -q -O - --header='Content-Type: application/json' --post-data="$1" http://127.0.0.1:18080/ubus
}
allowed=$(post "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"call\",\"params\":[\"$reader\",\"owrtpc\",\"status\",{}]}")
[ "$(printf '%s' "$allowed" | jsonfilter -e '@.result[0]')" = 0 ]
for session in 00000000000000000000000000000000 "$reader"; do
    for method in profile_apply profile_create profile_delete profiles_reorder set_enabled set_block add_time refresh reset; do
        denied=$(post "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"call\",\"params\":[\"$session\",\"owrtpc\",\"$method\",{\"confirmation\":\"RESET OWRTPC\"}]}")
        [ "$(printf '%s' "$denied" | jsonfilter -e '@.error.code')" = -32002 ] || {
            echo "FAIL: HTTP write ACL $method"; exit 1;
        }
    done
done
echo 'PASS: HTTP ubus enforces anonymous/read-only write denials'

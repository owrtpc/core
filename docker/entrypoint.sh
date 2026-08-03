#!/bin/sh
# SPDX-License-Identifier: Apache-2.0

set -eu

UBUS_SOCKET=/var/run/ubus/ubus.sock
UBUSD_PID=''
PROCD_PID=''
RPCD_PID=''
OWRTPC_PID=''

cleanup() {
	[ -z "$OWRTPC_PID" ] || kill "$OWRTPC_PID" 2>/dev/null || true
	[ -z "$RPCD_PID" ] || kill "$RPCD_PID" 2>/dev/null || true
	[ -z "$PROCD_PID" ] || kill "$PROCD_PID" 2>/dev/null || true
	[ -z "$UBUSD_PID" ] || kill "$UBUSD_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

mkdir -p /tmp/lock /tmp/log /var/run/ubus /etc/owrtpc/state

# Test-only credential: root / owrtpc
sed -i 's|^root:[^:]*:|root:$6$icD/b9YqGh.Hy.gL$z4f7n9yVotKFBaSppxrDde49rQPhGPRJKmiCWOj9RwLomeJD0Uv58DwKNfabtDXVT5cgZuHqe.WpK1j0aK7/v1:|' /etc/shadow

if [ -x /etc/uci-defaults/90-owrtpc ]; then
	/etc/uci-defaults/90-owrtpc
fi

# netifd is intentionally not started in Docker. Use the container interface
# directly while keeping wan/wan6 as the defaults in the distributable package.
uci -q delete owrtpc.main.monitored_network || true
uci -q delete owrtpc.main.monitored_device || true
uci add_list owrtpc.main.monitored_device='eth0'
uci commit owrtpc

/sbin/ubusd -s "$UBUS_SOCKET" &
UBUSD_PID=$!
attempt=0
while [ ! -S "$UBUS_SOCKET" ]; do
	attempt=$((attempt + 1))
	[ "$attempt" -lt 10 ] || { echo 'ubusd did not create its socket' >&2; exit 1; }
	sleep 1
done

mkdir -p /tmp/owrtpc-empty-init
/sbin/procd -s "$UBUS_SOCKET" \
	-I /tmp/owrtpc-empty-init \
	-R /tmp/owrtpc-empty-init \
	-S &
PROCD_PID=$!

attempt=0
while ! ubus -s "$UBUS_SOCKET" list system >/dev/null 2>&1; do
	attempt=$((attempt + 1))
	[ "$attempt" -lt 10 ] || { echo 'procd did not register the system object' >&2; exit 1; }
	sleep 1
done

/sbin/rpcd -s "$UBUS_SOCKET" &
RPCD_PID=$!

/usr/sbin/owrtpcd &
OWRTPC_PID=$!

echo 'OWRTPC test router ready at http://localhost:8080/ (root / owrtpc)'
exec /usr/sbin/uhttpd -f \
	-h /www \
	-r 'OWRTPC Docker' \
	-x /cgi-bin \
	-u /ubus \
	-t 60 \
	-T 30 \
	-p 0.0.0.0:80

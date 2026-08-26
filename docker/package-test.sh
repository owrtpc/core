#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Container-only test. /project is mounted read-only; never run on a router.
set -eu
mode=$1
backend=/packages/owrtpc-0.1.0_alpha1-r22.apk
frontend=/packages/luci-app-owrtpc-0.1.0_alpha1-r22.apk
legacy=/legacy/luci-app-owrtpc-0.1.0_alpha1-r20.apk
[ -f /.dockerenv ] || { echo 'Docker only' >&2; exit 1; }
mkdir -p /tmp/lock /tmp/log /var/run/ubus
# No external repositories. Normal dependency solving stays enabled.
: > /etc/apk/repositories
/sbin/ubusd &
for attempt in 1 2 3 4 5; do
	[ ! -S /var/run/ubus/ubus.sock ] || break
	sleep 1
done
mkdir -p /tmp/empty-init
/sbin/procd -s /var/run/ubus/ubus.sock -I /tmp/empty-init -R /tmp/empty-init -S &
ubus -t 30 wait_for service
/etc/init.d/rpcd start
ubus -t 30 wait_for session
if [ "$mode" = headless ]; then
	# Pin actual backend dependencies, then remove all of LuCI.
	apk add rpcd rpcd-mod-luci firewall4 nftables-json jshn jsonfilter uci ubus
	apk del --rdepends luci-base
	! apk info -e luci-base
	[ ! -e /www/luci-static/resources/luci.js ]
fi
if [ "$mode" = upgrade ]; then
	apk --keys-dir /project/keys verify "$legacy"
	apk --allow-untrusted add "$legacy"
	uci set owrtpc.main.sample_interval=3600
	uci set owrtpc.main.activity_threshold_bytes=262144
	uci set owrtpc.preserved=profile
	uci set owrtpc.preserved.name='Preserved profile'
	uci set owrtpc.preserved.daily_minutes=90
	uci add_list owrtpc.preserved.device=02:11:22:33:44:55
	uci commit owrtpc
	/etc/init.d/owrtpc restart
	sleep 1
	mkdir -p /tmp/owrtpc /etc/owrtpc/state
	date +%F > /tmp/owrtpc/date
	printf '321\n' > /tmp/owrtpc/profile-preserved.used
	printf '3600\n' > /tmp/owrtpc/profile-preserved.bonus
	printf '123\n' > /tmp/owrtpc/device-02_11_22_33_44_55.used
	owrtpcctl checkpoint
	cp /etc/config/owrtpc /tmp/expected-config
	# Unsafe direct installation must be rejected before changing files.
	if apk --allow-untrusted add "$backend"; then
		echo 'FAIL: backend accepted the legacy file owner' >&2; exit 1
	fi
	cmp /etc/config/owrtpc /tmp/expected-config
	sh /project/scripts/migrate-monolith.sh prepare
	cmp /etc/config/owrtpc /tmp/expected-config
else
	if apk --allow-untrusted add "$frontend"; then
		echo 'FAIL: frontend installed without backend' >&2; exit 1
	fi
fi
apk --allow-untrusted add "$backend"
apk info --who-owns /usr/sbin/owrtpcctl | grep -q 'owrtpc-'
apk info --who-owns /usr/libexec/rpcd/owrtpc | grep -q 'owrtpc-'
apk info --who-owns /usr/share/rpcd/acl.d/owrtpc.json | grep -q 'owrtpc-'
grep -qx '/etc/config/owrtpc' /lib/apk/packages/owrtpc.conffiles
grep -qx '/etc/owrtpc/state/' /lib/upgrade/keep.d/owrtpc
if [ "$mode" = upgrade ]; then
	cmp /etc/config/owrtpc /tmp/expected-config
	[ "$(cat /tmp/owrtpc/profile-preserved.used)" = 321 ]
	[ "$(cat /etc/owrtpc/state/profile-preserved.used)" = 321 ]
	[ "$(cat /tmp/owrtpc/profile-preserved.bonus)" = 3600 ]
	[ "$(cat /tmp/owrtpc/device-02_11_22_33_44_55.used)" = 123 ]
fi
uci -q delete owrtpc.main.monitored_network || true
uci add_list owrtpc.main.monitored_device=eth0
uci set owrtpc.main.sample_interval=3600
uci commit owrtpc
/etc/init.d/owrtpc restart
/etc/init.d/rpcd restart
ubus -t 30 wait_for owrtpc luci-rpc session
owrtpcctl validate | grep -qx OK
[ -x /usr/share/owrtpc/firewall.include ]
nft delete table inet owrtpc
/usr/share/owrtpc/firewall.include
nft list table inet owrtpc >/dev/null
ubus call owrtpc status | grep -q profiles
ubus call luci-rpc getDHCPLeases | grep -q dhcp_leases
# Discovery must return data, not merely a registered empty object.
uci set dhcp.package_test=host
uci set dhcp.package_test.name=owrtpc-discovery-test
uci set dhcp.package_test.mac=02:AA:BB:CC:DD:EE
uci set dhcp.package_test.ip=192.168.1.99
uci commit dhcp
ubus call luci-rpc getHostHints | grep -q owrtpc-discovery-test
# Authenticate a restricted client with only the backend grant.
uci set rpcd.package_test=login
uci set rpcd.package_test.username=owrtpc-test
sed -i 's|^root:[^:]*:|root:$6$icD/b9YqGh.Hy.gL$z4f7n9yVotKFBaSppxrDde49rQPhGPRJKmiCWOj9RwLomeJD0Uv58DwKNfabtDXVT5cgZuHqe.WpK1j0aK7/v1:|' /etc/shadow
uci set rpcd.package_test.password='$p$root'
uci add_list rpcd.package_test.read=owrtpc
uci add_list rpcd.package_test.write=owrtpc
uci commit rpcd
/etc/init.d/rpcd restart
ubus -t 30 wait_for owrtpc luci-rpc session
session=$(ubus call session login '{"username":"owrtpc-test","password":"owrtpc"}' | jsonfilter -e '@.ubus_rpc_session')
[ -n "$session" ]
check_access() {
	ubus call session access "{\"ubus_rpc_session\":\"$session\",\"scope\":\"$1\",\"object\":\"$2\",\"function\":\"$3\"}" |
		jsonfilter -e '@.access' | grep -qx true
}
check_access ubus owrtpc status
check_access ubus owrtpc set_block
check_access ubus luci-rpc getHostHints
check_access uci owrtpc write
if check_access uci firewall write; then
	echo 'FAIL: backend ACL grants firewall writes' >&2; exit 1
fi
sh /project/docker/policy-test.sh
if [ "$mode" != headless ]; then
	apk --allow-untrusted add "$frontend"
	ubus -t 30 wait_for session owrtpc luci-rpc
	apk info --who-owns /www/luci-static/resources/view/owrtpc/profiles-v2.js | grep -q luci-app-owrtpc
	/usr/sbin/uhttpd -f -h /www -x /cgi-bin -u /ubus -p 127.0.0.1:80 &
	sleep 1
	# LuCI correctly returns 403 with a login page for anonymous requests.
	# Authenticate and check that its dispatcher serves the OWRTPC view.
	ui_session=$(ubus call session login '{"username":"root","password":"owrtpc"}' | jsonfilter -e '@.ubus_rpc_session')
	# Match LuCI session_setup(): authenticated sessions carry a CSRF token.
	ubus call session set "{\"ubus_rpc_session\":\"$ui_session\",\"values\":{\"token\":\"owrtpc-package-test\"}}"
	wget -q --header="Cookie: sysauth_http=$ui_session" -O /tmp/luci.html http://127.0.0.1/cgi-bin/luci/admin/services/owrtpc
	grep -q 'owrtpc/profiles-v2' /tmp/luci.html
	wget -q -O - http://127.0.0.1/luci-static/resources/view/owrtpc/profiles-v2.js | grep -q 'callStatus'
	pid_before=$(pidof owrtpcd)
	[ -n "$pid_before" ]
	apk del luci-app-owrtpc
	[ "$(pidof owrtpcd)" = "$pid_before" ]
	[ ! -e /www/luci-static/resources/view/owrtpc/profiles-v2.js ]
	apk info -e owrtpc
	/etc/init.d/rpcd restart
	ubus -t 30 wait_for owrtpc luci-rpc session
	ubus call owrtpc status | grep -q profiles
	ubus call luci-rpc getHostHints | grep -q owrtpc-discovery-test
	# A fresh login, after rpcd reload, must still receive backend permissions.
	session=$(ubus call session login '{"username":"owrtpc-test","password":"owrtpc"}' | jsonfilter -e '@.ubus_rpc_session')
	check_access ubus owrtpc set_block
	check_access ubus luci-rpc getHostHints
	check_access uci owrtpc write
	sh /project/docker/policy-test.sh
fi
echo "PASS: package lifecycle $mode"

#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Container-only test. /project is mounted read-only; never run on a router.
set -eu
mode=$1
version=$(sed -n 's/^PKG_VERSION:=//p' /project/owrtpc/Makefile)
release=$(sed -n 's/^PKG_RELEASE:=//p' /project/owrtpc/Makefile)
backend=/packages/owrtpc-$version-r$release.apk
frontend=/packages/luci-app-owrtpc-$version-r$release.apk
legacy=/legacy/luci-app-owrtpc-0.1.0_alpha1-r20.apk
[ -f /.dockerenv ] || { echo 'Docker only' >&2; exit 1; }
# Fail early if the host cannot exercise the real firewall (e.g. QEMU user mode).
nft list tables >/dev/null
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
if [ "$mode" = upgrade ] || [ "$mode" = split-upgrade ]; then
	if [ "$mode" = upgrade ]; then
		apk --keys-dir /project/keys verify "$legacy"
		apk --allow-untrusted add "$legacy"
	else
		for name in owrtpc luci-app-owrtpc; do
			apk --keys-dir /project/keys verify "/legacy/$name-0.1.0_alpha1-r22.apk"
			apk --allow-untrusted add "/legacy/$name-0.1.0_alpha1-r22.apk"
		done
		# The reset UI must not install against a backend without reset support.
		if apk --allow-untrusted add "$frontend"; then
			echo 'FAIL: r23 frontend accepted r22 backend' >&2; exit 1
		fi
	fi
	uci set owrtpc.main.sample_interval=3600
	uci set owrtpc.main.activity_threshold_bytes=262144
	uci set owrtpc.preserved=profile
	uci set owrtpc.preserved.name='Preserved profile'
	uci set owrtpc.preserved.daily_minutes=90
	uci set owrtpc.preserved.weekday_daily_minutes=60
	uci set owrtpc.preserved.weekend_daily_minutes=120
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
	if [ "$mode" = upgrade ]; then
		# Unsafe direct installation must be rejected before changing files.
		if apk --allow-untrusted add "$backend"; then
			echo 'FAIL: backend accepted the legacy file owner' >&2; exit 1
		fi
		cmp /etc/config/owrtpc /tmp/expected-config
		sh /project/scripts/migrate-monolith.sh prepare
	fi
	cmp /etc/config/owrtpc /tmp/expected-config
else
	if apk --allow-untrusted add "$frontend"; then
		echo 'FAIL: frontend installed without backend' >&2; exit 1
	fi
fi
apk --allow-untrusted add "$backend"
[ ! -x /etc/uci-defaults/90-owrtpc ] || /etc/uci-defaults/90-owrtpc
apk info --who-owns /usr/sbin/owrtpcctl | grep -q 'owrtpc-'
apk info --who-owns /usr/libexec/rpcd/owrtpc | grep -q 'owrtpc-'
apk info --who-owns /usr/share/rpcd/acl.d/owrtpc.json | grep -q 'owrtpc-'
grep -qx '/etc/config/owrtpc' /lib/apk/packages/owrtpc.conffiles
grep -qx '/etc/owrtpc/state/' /lib/upgrade/keep.d/owrtpc
if [ "$mode" = upgrade ] || [ "$mode" = split-upgrade ]; then
	# Exercise bedtime migration after upgrade without making package restart
	# behavior depend on the container's wall clock.
	uci set owrtpc.preserved.weekday_bedtime_start=21:30
	uci set owrtpc.preserved.weekday_bedtime_end=07:00
	uci set owrtpc.preserved.weekend_bedtime_start=23:00
	uci set owrtpc.preserved.weekend_bedtime_end=09:00
	uci commit owrtpc
	/project/owrtpc/files/etc/uci-defaults/90-owrtpc
	[ "$(uci -q get owrtpc.main.sample_interval)" = 3600 ]
	[ "$(uci -q get owrtpc.main.activity_threshold_bytes)" = 262144 ]
	[ "$(uci -q get owrtpc.preserved.mon_thu_daily_minutes)" = 60 ]
	[ "$(uci -q get owrtpc.preserved.fri_sun_daily_minutes)" = 120 ]
	[ "$(uci -q get owrtpc.preserved.sun_thu_bedtime_start)" = 21:30 ]
	[ "$(uci -q get owrtpc.preserved.sun_thu_bedtime_end)" = 07:00 ]
	[ "$(uci -q get owrtpc.preserved.fri_sat_bedtime_start)" = 23:00 ]
	[ "$(uci -q get owrtpc.preserved.fri_sat_bedtime_end)" = 09:00 ]
	! uci -q get owrtpc.preserved.daily_minutes >/dev/null
	! uci -q get owrtpc.preserved.weekday_daily_minutes >/dev/null
	! uci -q get owrtpc.preserved.weekend_daily_minutes >/dev/null
	[ "$(uci -q get owrtpc.preserved.name)" = 'Preserved profile' ]
	[ "$(uci -q get owrtpc.preserved.device)" = '02:11:22:33:44:55' ]
	[ "$(cat /tmp/owrtpc/profile-preserved.used)" = 321 ]
	[ "$(cat /etc/owrtpc/state/profile-preserved.used)" = 321 ]
	[ "$(cat /tmp/owrtpc/profile-preserved.bonus)" = 3600 ]
	[ "$(cat /tmp/owrtpc/device-02_11_22_33_44_55.used)" = 123 ]
fi
uci -q delete owrtpc.main.monitored_network || true
uci add_list owrtpc.main.monitored_device=eth0
uci set owrtpc.main.sample_interval=3600
uci set owrtpc.package_details=profile
uci set owrtpc.package_details.name='Package details fixture'
uci set owrtpc.package_details.enabled=1
uci set owrtpc.package_details.mon_thu_daily_minutes=60
uci add_list owrtpc.package_details.device=02:AA:BB:CC:DD:EF
uci commit owrtpc
/etc/init.d/owrtpc restart
/etc/init.d/rpcd restart
ubus -t 30 wait_for owrtpc luci-rpc session
owrtpcctl validate | grep -qx OK
[ -x /usr/share/owrtpc/firewall.include ]
nft delete table inet owrtpc
/usr/share/owrtpc/firewall.include
nft list table inet owrtpc >/dev/null
printf '456\n' > /tmp/owrtpc/device-02AABBCCDDEF.used
status=$(ubus call owrtpc status)
printf '%s\n' "$status" | grep -q profiles
printf '%s\n' "$status" | grep -q '02:AA:BB:CC:DD:EF'
printf '%s\n' "$status" | grep -q '"used_seconds": 456'
capabilities=$(ubus call owrtpc capabilities)
printf '%s\n' "$capabilities" | jsonfilter -e '@.api' | grep -qx owrtpc-mobile
printf '%s\n' "$capabilities" | jsonfilter -e '@.major' | grep -qx 1
printf '%s\n' "$capabilities" | jsonfilter -e '@.minor' | grep -qx 6
[ "$(printf '%s\n' "$capabilities" | jsonfilter -e '@.backend_version')" = "$version-r$release" ]
printf '%s\n' "$capabilities" | jsonfilter -e '@.features[*]' | grep -qx profiles.read
printf '%s\n' "$capabilities" | jsonfilter -e '@.features[*]' | grep -qx profiles.write
printf '%s\n' "$capabilities" | jsonfilter -e '@.features[*]' | grep -qx quick-actions
printf '%s\n' "$capabilities" | jsonfilter -e '@.features[*]' | grep -qx device-discovery
printf '%s\n' "$capabilities" | jsonfilter -e '@.features[*]' | grep -qx uci-apply-confirm
printf '%s\n' "$capabilities" | jsonfilter -e '@.features[*]' | grep -qx schedule-periods
printf '%s\n' "$capabilities" | jsonfilter -e '@.features[*]' | grep -qx device-usage
printf '%s\n' "$capabilities" | jsonfilter -e '@.features[*]' | grep -qx profile-edit-transaction
printf '%s\n' "$capabilities" | jsonfilter -e '@.features[*]' | grep -qx profile-create-transaction
printf '%s\n' "$capabilities" | jsonfilter -e '@.router_date' | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
printf '%s\n' "$capabilities" | jsonfilter -e '@.router_timezone' | grep -q .
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
check_access ubus owrtpc capabilities
check_access ubus owrtpc edit_snapshot
check_access ubus owrtpc profile_apply
check_access ubus owrtpc profile_create
check_access ubus owrtpc profiles_reorder
check_access ubus owrtpc profile_delete
check_access ubus owrtpc set_block
check_access ubus owrtpc reset
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

# Reset is a backend operation, tested after removing the UI and on a fully
# headless system as well. Keep identifiers/MACs unchanged to catch resurrection.
uci set owrtpc.reset_test=profile
uci set owrtpc.reset_test.name='Reset fixture'
uci set owrtpc.reset_test.enabled=1
uci set owrtpc.reset_test.blocked=1
uci set owrtpc.reset_test.daily_minutes=60
uci add_list owrtpc.reset_test.device=02:11:22:33:44:56
uci commit owrtpc
/etc/init.d/owrtpc restart
owrtpcctl init
printf '321\n' > /tmp/owrtpc/profile-reset_test.used
printf '3600\n' > /tmp/owrtpc/profile-reset_test.bonus
printf '1\n' > /tmp/owrtpc/profile-reset_test.all_day
printf '123\n' > /tmp/owrtpc/device-02_11_22_33_44_56.used
printf '1\n' > /tmp/owrtpc/device-02_11_22_33_44_56.activity-active
owrtpcctl checkpoint
nft list table inet owrtpc | grep -q owrtpc-block:manual
cp /etc/config/owrtpc /tmp/reset-before-config
if owrtpcctl reset; then
	echo 'FAIL: CLI reset accepted missing confirmation' >&2; exit 1
fi
for request in '{}' '{"confirmation":"RESET"}' '{"confirmation":true}'; do
	ubus call owrtpc reset "$request" | jsonfilter -e '@.success' | grep -qx false
done
cmp /etc/config/owrtpc /tmp/reset-before-config
[ "$(cat /tmp/owrtpc/profile-reset_test.used)" = 321 ]
mkdir /var/lock/owrtpc-action.lock
ubus call owrtpc reset '{"confirmation":"RESET OWRTPC"}' | jsonfilter -e '@.error' | grep -q 'OWRTPC is busy'
rmdir /var/lock/owrtpc-action.lock
cmp /etc/config/owrtpc /tmp/reset-before-config
mv /etc/owrtpc/state /etc/owrtpc/state.saved
ln -s /etc/owrtpc/state.saved /etc/owrtpc/state
ubus call owrtpc reset '{"confirmation":"RESET OWRTPC"}' | jsonfilter -e '@.error' | grep -q 'symlinked'
rm /etc/owrtpc/state
mv /etc/owrtpc/state.saved /etc/owrtpc/state
cmp /etc/config/owrtpc /tmp/reset-before-config

# A read-only login must not acquire the destructive method.
uci set rpcd.reset_reader=login
uci set rpcd.reset_reader.username=owrtpc-reader
uci set rpcd.reset_reader.password='$p$root'
uci add_list rpcd.reset_reader.read=owrtpc
uci commit rpcd
/etc/init.d/rpcd restart
ubus -t 30 wait_for session owrtpc
session=$(ubus call session login '{"username":"owrtpc-reader","password":"owrtpc"}' | jsonfilter -e '@.ubus_rpc_session')
check_access ubus owrtpc status
sh /project/docker/http-acl-test.sh "$session"
if check_access ubus owrtpc reset; then
	echo 'FAIL: read-only user may reset' >&2; exit 1
fi
if check_access ubus owrtpc profiles_reorder; then
	echo 'FAIL: read-only user may reorder profiles' >&2; exit 1
fi
if check_access ubus owrtpc profile_delete; then
	echo 'FAIL: read-only user may delete profiles' >&2; exit 1
fi
session=$(ubus call session login '{"username":"owrtpc-test","password":"owrtpc"}' | jsonfilter -e '@.ubus_rpc_session')
check_access ubus owrtpc reset
ubus call uci set "{\"ubus_rpc_session\":\"$session\",\"config\":\"owrtpc\",\"section\":\"main\",\"values\":{\"enabled\":\"0\"}}"
ubus call owrtpc reset '{"confirmation":"RESET OWRTPC"}' | jsonfilter -e '@.error' | grep -q 'pending OWRTPC changes'
cmp /etc/config/owrtpc /tmp/reset-before-config
/etc/init.d/owrtpc running
ubus call uci revert "{\"ubus_rpc_session\":\"$session\",\"config\":\"owrtpc\"}"
mkdir -p /var/run/rpcd/snapshot-files
cp /etc/config/owrtpc /var/run/rpcd/snapshot-files/owrtpc
ubus call owrtpc reset '{"confirmation":"RESET OWRTPC"}' | jsonfilter -e '@.error' | grep -q 'pending OWRTPC changes'
rm /var/run/rpcd/snapshot-files/owrtpc
# Missing packaged defaults must fail without stopping or deleting anything.
mv /usr/share/owrtpc/defaults/owrtpc /usr/share/owrtpc/defaults/owrtpc.saved
ubus call owrtpc reset '{"confirmation":"RESET OWRTPC"}' | jsonfilter -e '@.success' | grep -qx false
mv /usr/share/owrtpc/defaults/owrtpc.saved /usr/share/owrtpc/defaults/owrtpc
cmp /etc/config/owrtpc /tmp/reset-before-config
/etc/init.d/owrtpc running

# Preserve router settings, discoveries, signing keys and explicit backups.
mkdir -p /root/owrtpc-migration-test
printf 'keep backup\n' > /root/owrtpc-migration-test/config
printf 'config client preserved\n' > /etc/config/gl-client
if [ ! -e /etc/config/network ]; then printf 'config interface preserved\n' > /etc/config/network; fi
if [ ! -e /etc/config/wireless ]; then printf 'config wifi-device preserved\n' > /etc/config/wireless; fi
sha256sum /etc/config/firewall /etc/config/network /etc/config/wireless /etc/config/dhcp \
	/etc/config/rpcd /etc/config/gl-client /etc/shadow /etc/apk/keys/* \
	/root/owrtpc-migration-test/config > /tmp/reset-unrelated.sha256
nft add table inet reset_unrelated
nft add chain inet reset_unrelated preserved
ubus call owrtpc reset '{"confirmation":"RESET OWRTPC"}' | jsonfilter -e '@.success' | grep -qx true
cmp /etc/config/owrtpc /usr/share/owrtpc/defaults/owrtpc
sha256sum -c /tmp/reset-unrelated.sha256
nft list chain inet reset_unrelated preserved >/dev/null
nft list table inet owrtpc > /tmp/reset-rules
if grep -q 'owrtpc-block:\|owrtpc-device:' /tmp/reset-rules; then
	echo 'FAIL: old reset rules remain' >&2; exit 1
fi
/etc/init.d/owrtpc running
owrtpcctl validate | grep -qx OK
! uci show owrtpc | grep -q '=profile'
for dir in /tmp/owrtpc /etc/owrtpc/state; do
	[ ! -e "$dir/profile-reset_test.used" ]
	[ ! -e "$dir/profile-reset_test.bonus" ]
	[ ! -e "$dir/profile-reset_test.all_day" ]
	[ ! -e "$dir/device-02_11_22_33_44_56.used" ]
	[ ! -e "$dir/device-02_11_22_33_44_56.activity-active" ]
done
# Reusing the exact section/MAC and restarting must not revive today's data.
uci set owrtpc.reset_test=profile
uci set owrtpc.reset_test.name='New profile'
uci set owrtpc.reset_test.daily_minutes=60
uci add_list owrtpc.reset_test.device=02:11:22:33:44:56
uci commit owrtpc
/etc/init.d/owrtpc restart
owrtpcctl init
ubus call owrtpc status | jsonfilter -e '@.profiles[0].used_seconds' | grep -qx 0
ubus call owrtpc status | jsonfilter -e '@.profiles[0].bonus_seconds' | grep -qx 0
owrtpcctl diagnostics | grep -q '02:11:22:33:44:56.*0'
if [ "$mode" = clean ]; then
	# A post-deletion error must report partial failure, never false success.
	mkdir /tmp/reset-failbin
	printf '#!/bin/sh\nexit 1\n' > /tmp/reset-failbin/nft
	chmod 0755 /tmp/reset-failbin/nft
	if PATH="/tmp/reset-failbin:$PATH" owrtpcctl reset --confirm > /tmp/reset-failure 2>&1; then
		echo 'FAIL: reset succeeded despite failed firewall initialization' >&2; exit 1
	fi
	grep -q 'Data was reset, but OWRTPC policy initialization failed' /tmp/reset-failure
	! /etc/init.d/owrtpc running
	cmp /etc/config/owrtpc /usr/share/owrtpc/defaults/owrtpc
fi
# Reset must also recover missing/broken active configuration, via CLI.
printf 'invalid UCI input\n' > /etc/config/owrtpc
owrtpcctl reset --confirm
cmp /etc/config/owrtpc /usr/share/owrtpc/defaults/owrtpc
/etc/init.d/owrtpc running
echo 'PASS: full reset, confirmation, ACLs, staged changes, preserved router data and restart'
echo "PASS: package lifecycle $mode"

#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
set -e
[ -f /.dockerenv ] || exit 1
. /usr/share/libubox/jshn.sh
work=$(mktemp -d /tmp/owrtpc-order-test.XXXXXX)
cp /etc/config/owrtpc "$work/original"
cleanup() {
	cp "$work/original" /etc/config/owrtpc
	owrtpcctl apply >/dev/null
	rm -rf "$work"
}
trap cleanup EXIT

# Include two truly anonymous profiles and a non-profile section between them.
first=$(uci add owrtpc profile)
uci set "owrtpc.$first.name=Order First"
uci set "owrtpc.$first.enabled=0"
uci set owrtpc.order_marker=metadata
uci set owrtpc.order_marker.value=preserved
second=$(uci add owrtpc profile)
uci set "owrtpc.$second.name=Order Second"
uci set "owrtpc.$second.enabled=0"
uci commit owrtpc
owrtpcctl apply >/dev/null
cp /etc/config/owrtpc "$work/before"
uci -X show owrtpc | sort > "$work/options-before"
uci -X show owrtpc | grep -E '^[^.]+\.[^.]+=' | awk '{print NR, $0}' | grep -v '=profile$' > "$work/nonprofiles-before"
ubus call owrtpc edit_snapshot | jsonfilter -e '@.profiles[*].section' > "$work/order"
awk '{a[NR]=$0} END {for(i=NR;i>0;i--) print a[i]}' "$work/order" > "$work/reversed"
revision=$(ubus call owrtpc edit_snapshot | jsonfilter -e '@.revision')
request() {
	json_init
	json_add_string expected_revision "$1"
	json_add_array profiles
	while IFS= read -r section; do json_add_string '' "$section"; done < "$2"
	json_close_array
	json_dump
}
payload=$(request "$revision" "$work/reversed")
expect_error() {
	ubus call owrtpc profiles_reorder "$1" | jsonfilter -e '@.code' | grep -qx "$2"
	cmp /etc/config/owrtpc "$work/before"
}
expect_error "$(request "$(printf '%064d' 0)" "$work/reversed")" conflicting_edit
expect_error '{"expected_revision":"bad","profiles":[]}' invalid_request
expect_error "{\"expected_revision\":\"$revision\",\"profiles\":{}}" invalid_request
expect_error "{\"expected_revision\":\"$revision\",\"profiles\":[null]}" validation_failed
expect_error "{\"expected_revision\":\"$revision\",\"profiles\":[\"../config\"]}" validation_failed
expect_error "{\"expected_revision\":\"$revision\",\"profiles\":[\"main\"]}" validation_failed
sed '$d' "$work/reversed" > "$work/incomplete"
expect_error "$(request "$revision" "$work/incomplete")" validation_failed
cat "$work/reversed" "$work/reversed" > "$work/duplicates"
expect_error "$(request "$revision" "$work/duplicates")" validation_failed
uci set owrtpc.order_marker.value=pending
expect_error "$payload" conflicting_edit
uci changes owrtpc | grep -q pending
uci revert owrtpc

# Fail policy application once, then prove exact configuration/firewall restore.
cat > "$work/engine" <<EOF
#!/bin/sh
if [ "\$1" = apply ] && [ ! -f '$work/failed' ]; then
    touch '$work/failed'
    exit 1
fi
exec /usr/sbin/owrtpcctl "\$@"
EOF
chmod 0755 "$work/engine"
sed "s|^OWRTPCCTL=.*|OWRTPCCTL=$work/engine|" /usr/libexec/rpcd/owrtpc > "$work/rpc"
nft -s list table inet owrtpc > "$work/firewall-before"
printf '%s\n' "$payload" | sh "$work/rpc" call profiles_reorder | jsonfilter -e '@.code' | grep -qx apply_failed
cmp /etc/config/owrtpc "$work/before"
nft -s list table inet owrtpc > "$work/firewall-after"
cmp "$work/firewall-before" "$work/firewall-after"

# Always failing application must never claim restoration succeeded.
cat > "$work/engine" <<'EOF'
#!/bin/sh
[ "$1" != apply ] || exit 1
exec /usr/sbin/owrtpcctl "$@"
EOF
printf '%s\n' "$payload" | sh "$work/rpc" call profiles_reorder | jsonfilter -e '@.code' | grep -qx outcome_unknown
cmp /etc/config/owrtpc "$work/before"

printf '123\n' > "/tmp/owrtpc/profile-$first.used"
printf '456\n' > "/tmp/owrtpc/profile-$second.used"
printf '3600\n' > "/tmp/owrtpc/profile-$first.bonus"
owrtpcctl checkpoint
result=$(ubus call owrtpc profiles_reorder "$payload")
printf '%s\n' "$result" | jsonfilter -e '@.success' | grep -qx true
updated_revision=$(printf '%s\n' "$result" | jsonfilter -e '@.revision')
[ "$updated_revision" != "$revision" ]
snapshot=$(ubus call owrtpc edit_snapshot)
[ "$(printf '%s\n' "$snapshot" | jsonfilter -e '@.revision')" = "$updated_revision" ]
printf '%s\n' "$snapshot" | jsonfilter -e '@.profiles[*].section' > "$work/actual"
cmp "$work/actual" "$work/reversed"
ubus call owrtpc status | jsonfilter -e '@.profiles[*].section' > "$work/live"
cmp "$work/live" "$work/reversed"
uci -X show owrtpc | sort > "$work/options-after"
cmp "$work/options-before" "$work/options-after"
uci -X show owrtpc | grep -E '^[^.]+\.[^.]+=' | awk '{print NR, $0}' | grep -v '=profile$' > "$work/nonprofiles-after"
cmp "$work/nonprofiles-before" "$work/nonprofiles-after"
[ "$(uci get "owrtpc.$first.name")" = 'Order First' ]
[ "$(uci get "owrtpc.$second.name")" = 'Order Second' ]
[ "$(cat "/tmp/owrtpc/profile-$first.used")" = 123 ]
[ "$(cat "/tmp/owrtpc/profile-$second.used")" = 456 ]
[ "$(cat "/tmp/owrtpc/profile-$first.bonus")" = 3600 ]
[ "$(cat "/etc/owrtpc/state/profile-$first.used")" = 123 ]
# A repeated old request conflicts; no second write is silently accepted.
ubus call owrtpc profiles_reorder "$payload" | jsonfilter -e '@.code' | grep -qx conflicting_edit
# A fresh no-op is valid and retains the revision.
result=$(ubus call owrtpc profiles_reorder "$(request "$updated_revision" "$work/reversed")")
[ "$(printf '%s\n' "$result" | jsonfilter -e '@.revision')" = "$updated_revision" ]
# Empty and single-profile configurations are valid permutations too.
printf "config settings 'main'\n\toption enabled '1'\n" > /etc/config/owrtpc
owrtpcctl apply >/dev/null
: > "$work/empty"
revision=$(ubus call owrtpc edit_snapshot | jsonfilter -e '@.revision')
ubus call owrtpc profiles_reorder "$(request "$revision" "$work/empty")" | jsonfilter -e '@.success' | grep -qx true
uci set owrtpc.only=profile
uci set owrtpc.only.name=Only
uci commit owrtpc
owrtpcctl apply >/dev/null
printf 'only\n' > "$work/single"
revision=$(ubus call owrtpc edit_snapshot | jsonfilter -e '@.revision')
ubus call owrtpc profiles_reorder "$(request "$revision" "$work/single")" | jsonfilter -e '@.success' | grep -qx true
echo 'PASS: transactional ordering, anonymous identities, counters, conflicts and rollback'

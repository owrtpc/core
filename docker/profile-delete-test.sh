#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Invoked from the Docker policy suite with its temporary created profile.
set -eu
[ -f /.dockerenv ] || exit 1
section=$1
snapshot=$(ubus call owrtpc edit_snapshot)
revision=$(printf '%s\n' "$snapshot" | jsonfilter -e '@.revision')
request="{\"expected_revision\":\"$revision\",\"section\":\"$section\"}"
cp /etc/config/owrtpc /tmp/owrtpc-delete-before.config
nft -s list table inet owrtpc > /tmp/owrtpc-delete-before.nft

# Reject stale revisions, invalid sections and another client's staged edits.
stale=$(printf '%064d' 0)
ubus call owrtpc profile_delete "{\"expected_revision\":\"$stale\",\"section\":\"$section\"}" | grep -q '"code": "conflicting_edit"'
ubus call owrtpc profile_delete "{\"expected_revision\":\"$revision\",\"section\":\"main\"}" | grep -q '"code": "not_found"'
ubus call owrtpc profile_delete "{\"expected_revision\":\"$revision\",\"section\":\"../config\"}" | grep -q '"code": "not_found"'
ubus call owrtpc profile_delete "{\"expected_revision\":\"invalid\",\"section\":\"$section\"}" | grep -q '"code": "invalid_request"'
uci set owrtpc.docker_test.name='Pending unrelated edit'
ubus call owrtpc profile_delete "$request" | grep -q '"code": "conflicting_edit"'
uci changes owrtpc | grep -q 'Pending unrelated edit'
uci revert owrtpc
cmp /etc/config/owrtpc /tmp/owrtpc-delete-before.config

# Real UCI and nftables, with only the first engine apply made to fail.
cat > /tmp/owrtpc-delete-engine <<'EOF'
#!/bin/sh
if [ "$1" = apply ] && [ ! -f /tmp/owrtpc-delete-failed-once ]; then
    touch /tmp/owrtpc-delete-failed-once
    exit 1
fi
exec /usr/sbin/owrtpcctl "$@"
EOF
chmod 0755 /tmp/owrtpc-delete-engine
sed 's|^OWRTPCCTL=.*|OWRTPCCTL=/tmp/owrtpc-delete-engine|' /usr/libexec/rpcd/owrtpc > /tmp/owrtpc-delete-rpc
printf '123\n' > "/tmp/owrtpc/profile-$section.used"
printf '3600\n' > "/tmp/owrtpc/profile-$section.bonus"
printf '1\n' > "/tmp/owrtpc/profile-$section.all_day"
owrtpcctl checkpoint
printf '%s\n' "$request" | sh /tmp/owrtpc-delete-rpc call profile_delete | grep -q '"code": "apply_failed"'
cmp /etc/config/owrtpc /tmp/owrtpc-delete-before.config
nft -s list table inet owrtpc > /tmp/owrtpc-delete-after.nft
cmp /tmp/owrtpc-delete-before.nft /tmp/owrtpc-delete-after.nft
[ "$(cat "/tmp/owrtpc/profile-$section.used")" = 123 ]
[ "$(uci get "owrtpc.$section")" = profile ]

# Successful deletion removes policy and profile state, preserving other data.
printf '77\n' > /tmp/owrtpc/profile-docker_test.used
printf '42\n' > /tmp/owrtpc/device-0242AC110003.used
owrtpcctl checkpoint
result=$(ubus call owrtpc profile_delete "$request")
printf '%s\n' "$result" | grep -q '"success": true'
[ "$(printf '%s\n' "$result" | jsonfilter -e '@.section')" = "$section" ]
! uci -q get "owrtpc.$section"
! ubus call owrtpc status | grep -q "\"section\": \"$section\""
! ubus call owrtpc edit_snapshot | grep -q "\"section\": \"$section\""
! nft list table inet owrtpc | grep -q '02:42:AC:11:00:03'
for directory in /tmp/owrtpc /etc/owrtpc/state; do
    for suffix in used bonus all_day; do
        [ ! -e "$directory/profile-$section.$suffix" ]
    done
done
[ "$(cat /tmp/owrtpc/profile-docker_test.used)" = 77 ]
[ "$(cat /tmp/owrtpc/device-0242AC110003.used)" = 42 ]
if owrtpcctl forget-profile docker_test; then
    echo 'FAIL: active profile state was removed' >&2; exit 1
fi
ubus call owrtpc profile_delete "$request" | grep -q '"code": "conflicting_edit"'
rm -f /tmp/owrtpc-delete-engine /tmp/owrtpc-delete-rpc /tmp/owrtpc-delete-failed-once
echo 'PASS: profile deletion, conflict, rollback and state preservation'

#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# jshn uses unset variables while implementing its dynamic JSON namespace.
set -e
[ -f /.dockerenv ] || exit 1
. /usr/share/libubox/jshn.sh
work=$(mktemp -d /tmp/owrtpc-write-check.XXXXXX)
trap 'rm -rf "$work"' EXIT
cp /etc/config/owrtpc "$work/config"
revision=$(ubus call owrtpc edit_snapshot | jsonfilter -e '@.revision')
request() {
    json_init
    json_add_string expected_revision "$revision"
    json_add_string section docker_test
    json_add_string name "$1"
    json_add_boolean enabled 1
    json_add_int mon_thu_daily_minutes 30
    json_add_int fri_sun_daily_minutes 30
    json_add_string sun_thu_bedtime_start ''
    json_add_string sun_thu_bedtime_end ''
    json_add_string fri_sat_bedtime_start ''
    json_add_string fri_sat_bedtime_end ''
    json_add_int activity_threshold_bytes 0
    json_add_array devices; json_close_array
    json_dump
}
for operation in profile_apply profile_create; do
    # Control characters must not create extra rows in CLI/RPC status output.
    for name in "$(printf 'line\nbreak')" "$(printf 'tab\tbreak')"; do
        ubus call owrtpc "$operation" "$(request "$name")" | grep -q '"code": "validation_failed"'
        cmp /etc/config/owrtpc "$work/config"
    done
    uci set owrtpc.main.checkpoint_interval=987
    ubus call owrtpc "$operation" "$(request 'Pending edit')" | grep -q '"code": "conflicting_edit"'
    uci changes owrtpc | grep -q 987
    uci revert owrtpc
    cmp /etc/config/owrtpc "$work/config"
done
# Fail real UCI commits only: no staged fields may leak into the global savedir.
real_uci=$(command -v uci)
mkdir "$work/bin"
cat > "$work/bin/uci" <<'EOF'
#!/bin/sh
for value in "$@"; do [ "$value" != commit ] || exit 1; done
exec "$REAL_UCI" "$@"
EOF
chmod 0755 "$work/bin/uci"
for operation in set_enabled set_block; do
    [ "$operation" != set_enabled ] || field=enabled
    [ "$operation" != set_block ] || field=blocked
    payload="{\"profile\":\"docker_test\",\"$field\":true}"
    uci set owrtpc.main.checkpoint_interval=987
    ubus call owrtpc "$operation" "$payload" | grep -q '"success": false'
    uci changes owrtpc | grep -q 987
    uci revert owrtpc
    cmp /etc/config/owrtpc "$work/config"
    printf '%s\n' "$payload" | REAL_UCI="$real_uci" PATH="$work/bin:$PATH" \
        sh /usr/libexec/rpcd/owrtpc call "$operation" | grep -q '"success": false'
    cmp /etc/config/owrtpc "$work/config"
    [ -z "$(uci changes owrtpc)" ]
done
for operation in profile_apply profile_create; do
    request 'Commit failure' | REAL_UCI="$real_uci" PATH="$work/bin:$PATH" \
        sh /usr/libexec/rpcd/owrtpc call "$operation" | grep -q '"code": "apply_failed"'
    cmp /etc/config/owrtpc "$work/config"
    [ -z "$(uci changes owrtpc)" ]
done
# A failed restore is reported as unknown, never as a successful rollback.
cat > "$work/engine" <<'EOF'
#!/bin/sh
[ "$1" != apply ] || exit 1
exec /usr/sbin/owrtpcctl "$@"
EOF
chmod 0755 "$work/engine"
sed "s|^OWRTPCCTL=.*|OWRTPCCTL=$work/engine|" /usr/libexec/rpcd/owrtpc > "$work/rpc"
request 'Failed policy restore' | sh "$work/rpc" call profile_apply | grep -q '"code": "outcome_unknown"'
cmp /etc/config/owrtpc "$work/config"
owrtpcctl apply >/dev/null
echo 'PASS: profile input, pending edits, isolated UCI failure and unknown rollback'

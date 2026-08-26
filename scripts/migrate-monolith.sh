#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Run on the target OpenWrt system, not on a development host.
set -eu

die() { echo "Migration stopped: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || die 'root is required'
[ -f /lib/apk/packages/luci-app-owrtpc.list ] || die 'the monolith is not installed'
grep -qx '/usr/sbin/owrtpcctl' /lib/apk/packages/luci-app-owrtpc.list ||
	die 'this is already the split LuCI package'
[ "$#" -eq 1 ] && [ "$1" = prepare ] ||
	die 'usage: sh migrate-monolith.sh prepare (read docs/INSTALL.md first)'

umask 077
backup=$(mktemp -d /root/owrtpc-migration.XXXXXX)
echo "Migration backup: $backup"
# Record the original configuration before stopping anything. Do not remove
# the backup on error: it is also the manual recovery source.
cp -p /etc/config/owrtpc "$backup/config"
cp -p /etc/config/firewall "$backup/firewall"
apk info -v luci-app-owrtpc > "$backup/package-version"
/etc/init.d/owrtpc stop
/usr/sbin/owrtpcctl checkpoint
for dir in /tmp/owrtpc /etc/owrtpc/state; do
	[ ! -d "$dir" ] || tar -cpf "$backup/$(basename "$dir").tar" -C "$dir" .
done
touch "$backup/backup-complete"

# Removing the old owner first avoids cross-package file replacement. apk
# preserves modified /etc files, but restore our exact copy regardless.
if ! apk del luci-app-owrtpc; then
	/etc/init.d/owrtpc start || true
	die "removal failed; backup retained at $backup"
fi
cp -p "$backup/config" /etc/config/owrtpc
cmp "$backup/config" /etc/config/owrtpc
echo "Monolith removed; configuration and state retained. Backup: $backup"
echo 'Install owrtpc first, then luci-app-owrtpc from the same release.'
echo 'Accounting is stopped until owrtpc is installed. Do not reboot in between.'

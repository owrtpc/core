# Installation and migration (OpenWrt 25.12+)

OWRTPC has two packages from r22 onward:

| Package | Contents | Required by |
| --- | --- | --- |
| `owrtpc` | Service, policy engine, CLI, UCI, firewall integration, RPC APIs and shared ACLs | All installations |
| `luci-app-owrtpc` | LuCI JavaScript, menu and translation sources | Optional web interface |

Install `owrtpc` first and `luci-app-owrtpc` second. The current packages use
version `0.1.0_alpha1-r25`; this UI requires backend r25 or newer. The backend
has no dependency on `luci-base` or any web UI. `rpcd-mod-luci` is a standalone
RPC module, required for DHCP leases and host hints despite its name.

No OWRTPC feed is configured or published. Package files must be supplied
locally. OpenWrt's configured feeds must provide their dependencies. Do not use
`--force-overwrite`, `--force-broken-world`, `--no-scripts` or forced removal.

## Before installing

Save a router configuration backup and keep the previous APK for recovery.
Verify each APK's `.sha256` against the supplied file on your computer. Keep
its `.buildinfo` alongside it. Trust the existing OWRTPC release public key
once on the router (never copy the private signing key):

```sh
cp /tmp/owrtpc-release.pem /etc/apk/keys/owrtpc-release.pem
chmod 0644 /etc/apk/keys/owrtpc-release.pem
apk update
apk verify /tmp/owrtpc-0.1.0_alpha1-r25.apk
apk verify /tmp/luci-app-owrtpc-0.1.0_alpha1-r25.apk
```

The public key is `keys/owrtpc-release.pem` in `owrtpc/core`. The split does not
change it. Release packages need no `--allow-untrusted`. APKs in `tmp/test-apks`
are unsigned development artifacts and must never be installed on a real router
or distributed as releases.

## Clean installation

```sh
apk add /tmp/owrtpc-0.1.0_alpha1-r25.apk
# Optional:
apk add /tmp/luci-app-owrtpc-0.1.0_alpha1-r25.apk
```

For a backend-only installation, stop after the first command. Local CLI and
ubus APIs are available; installation does not expose a new HTTP endpoint or
configure remote access. See [API.md](API.md) for the transport boundary.

### Manual upload from LuCI

After trusting the release public key, open **System > Software** (called
**Package Manager** on some LuCI versions), select **Upload Package**, and
upload `owrtpc-0.1.0_alpha1-r25.apk`. Wait for successful installation and
resolution of its dependencies. Then upload
`luci-app-owrtpc-0.1.0_alpha1-r25.apk` in a second operation. Refresh LuCI and
open **Services > Parental Control**.

Uploading the UI alone does not provide the local backend APK: it cannot be
resolved from official feeds. Install the backend first. On an offline router,
collect all missing OpenWrt dependency APKs for the same firmware/architecture
before starting; otherwise stop. Do not override a dependency or signature error.

## One-time migration from the monolith (r1-r21)

The old package was named `luci-app-owrtpc` but owned both backend and UI files.
A normal UI upload is **not** a supported migration. Do not install both new
APKs in one transaction while the monolith is present. The SDK does not emit
APK `replaces` metadata; r22 explicitly conflicts with the older file owner.
The backend pre-install script also detects remaining monolithic ownership.
Neither guard is a substitute for this procedure or a transaction rollback.

1. Download both new signed APKs, the public key, this document and
   `scripts/migrate-monolith.sh` from the same source commit. Copy them to the
   router's `/tmp`. Verify signatures and checksums first. Check free space
   and dependency availability **before** removing anything. Keep the old APK
   outside `/tmp` or on your computer.
2. Finish or discard pending LuCI configuration edits. Schedule a short
   maintenance window. Do not reboot, reload the firewall, or modify profiles
   until installation completes. Do not do this across local midnight.
3. Through SSH run:

   ```sh
   sh /tmp/migrate-monolith.sh prepare
   ```

   The helper stops accounting, forces a checkpoint, and saves the exact UCI
   configuration, firewall configuration, runtime state and persistent state
   under a private `/root/owrtpc-migration.XXXXXX` directory. It then removes
   the old package with APK and restores the exact configuration. Record and
   copy that backup off the router. It is not automatically deleted.
4. Install `owrtpc`, then optionally `luci-app-owrtpc`, using the commands above
   or the two manual LuCI uploads. Removing the OWRTPC monolith does not remove
   LuCI itself. Accounting is stopped during this interval. Existing nftables
   rules may remain, but enforcement updates are not guaranteed during
   maintenance; do not treat that interval as continuous protection.
5. Verify the checks below, profile settings and today's usage. APK may leave
   `/etc/config/owrtpc.apk-new` containing the new defaults. Your existing
   configuration remains active; do not overwrite it with the defaults.

This transfers file ownership by removing the old owner before adding the new
one, with no forced overwrites or edits to the APK database. Runtime/persistent
paths and profile identifiers do not change. The previous default-threshold
migration remains unchanged. Upgrades from older releases may still apply that
existing migration; custom thresholds remain preserved.

The real signed r20 APK has been used for local migration testing. The r1-r21
ownership layout is covered by the helper, but each historical binary has not
been individually verified. A firmware with additional vendor modifications
still needs its own validation; no Flint2 operation is part of this work.

### If migration stops

Do not reboot or delete the backup. A failure after removal leaves accounting
stopped. Resolve the installation error and install the backend, or reinstall
the saved monolithic APK to restore the previous version. If the split is partly
installed, remove its UI first, then its backend before reinstalling the old APK.
Restore `backup/config` to `/etc/config/owrtpc`; `owrtpc.tar` and `state.tar`
contain the contents of `/tmp/owrtpc` and `/etc/owrtpc/state` respectively. Stop
OWRTPC before restoring state, preserve the backup, and restart after recovery.
The engine intentionally discards usage/bonus belonging to a previous local day.

## Reset OWRTPC without reinstalling (r23+)

On **Services > Parental Control**, the **Reset OWRTPC** section contains a red
**Reset all OWRTPC data** button (standard LuCI `cbi-button-negative` styling).
The standard LuCI modal describes the consequences, offers Cancel and requires
typing `RESET OWRTPC` before enabling confirmation. A read-only account cannot
use the action. Save/apply or discard pending OWRTPC changes in all sessions
before resetting; do not edit from another tab during the operation.

This resets profiles, device assignments, counters, bonuses and OWRTPC engine
settings. Accounting stops briefly, data is erased and the service restarts
with the shipped defaults and no profiles. There are **no parental-control
blocks** until you create new profiles. The operation is immediate, not staged
behind Save & Apply, and needs neither package reinstallation nor router reboot.

Network/Wi-Fi settings, other firewall rules, DHCP/device discovery, passwords,
signing keys, existing backups and system logs remain. Export a backup first if
you may need the data; reset does not create a hidden copy of the erased data.
For a broken config that prevents the page loading, the root SSH equivalent is
`owrtpcctl reset --confirm`. On any error or lost connection, check current
status before retrying: reset may have already erased data. See [API.md](API.md)
for details and concurrency limits.

The button is available only **after** installing r23. It does not replace the
one-time monolith migration above. From the already split r22, simply upgrade
the backend first and the UI second; no removal or reset is required.

## Verification and subsequent upgrades

```sh
apk info -e owrtpc
apk info --who-owns /usr/sbin/owrtpcctl
owrtpcctl validate
owrtpcctl status
owrtpcctl diagnostics
ubus call owrtpc status
ubus call luci-rpc getHostHints
ubus call luci-rpc getDHCPLeases
nft list table inet owrtpc
```

After the split, ordinary upgrades replace each package's own files. Update the
backend before an interface requiring a newer backend. UCI configuration is a
conffile; persistent counters are included in OpenWrt's sysupgrade keep list.
This does not replace a backup or guarantee survival through a firmware reset.

To remove **only** the OWRTPC interface:

```sh
apk add owrtpc  # retain the backend explicitly in APK world
apk del luci-app-owrtpc
```

Do not request recursive removal of the backend. Service, config, counters,
firewall include, RPC plugin, discovery dependencies and shared ACLs belong to
`owrtpc` and remain installed. Removing `owrtpc` itself stops its service and
is not the same operation.

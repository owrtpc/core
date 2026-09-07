# Shared router API

The router component is `owrtpc/core`. Both LuCI and the `owrtpc/mobile`
client consume the router's state and policy engine; neither duplicates it.
This document describes the shared MVP contract and the versioned compatibility
handshake used by the mobile client. No remote access, relay service or web
filter is provided by this API.

## Objects and dependencies

| API | Operations | Provider |
| --- | --- | --- |
| `owrtpc` | `capabilities`, `status`, `edit_snapshot`, `profile_apply`, `profile_create`, `profile_delete`, `validate`, `refresh`, `set_enabled`, `set_block`, `add_time`, `reset` | `owrtpc` executable rpcd plugin |
| `uci` | profile/config reads and staged edits, apply/confirm | `rpcd` |
| `session` | login, access checks, logout | `rpcd` |
| `luci-rpc` | `getHostHints`, `getDHCPLeases` | `rpcd-mod-luci` |

`rpcd` loads shell plugins from `/usr/libexec/rpcd` itself; `rpcd-mod-file` is
not required for that mechanism. `jshn` provides JSON construction and parsing.
`uci`, `ubus`, `jsonfilter`, `firewall4` and `nftables-json` are explicit runtime
dependencies. Standard OpenWrt base-files/BusyBox provide the shell, config
helpers and common utilities. No `luci-base`, web dispatcher or JS package is
needed by the backend.

Host hints include standard OpenWrt configured DHCP names and discovered
addresses. DHCP leases and the configured profile MACs complete the device
list, including offline devices. LuCI's existing merge/search code stays in the
UI. Optional aliases can be read from UCI `gl-client` when present; that vendor
package is not a dependency and missing data must be tolerated. The mobile app
must use the same sources and precedence (alias, host hints, leases, MAC), not
assume GL.iNet firmware. No new discovery algorithm is introduced here.

## Permissions and configuration

`/usr/share/rpcd/acl.d/owrtpc.json` belongs to the backend. The stable grant is
`owrtpc`, with read-only `owrtpc` capabilities/status/validation, discovery and
UCI reads for `owrtpc`, `firewall`, and optional `gl-client`. Its write grant
permits the existing quick actions and UCI changes **only to `owrtpc`**, never
firewall or vendor configuration writes.

From r23 the write grant also permits the destructive `reset` method. Read-only
accounts cannot reset. This shared permission remains installed without LuCI.

The historical `luci-app-owrtpc` grant is an equivalent compatibility alias in
that same backend file. Existing restricted clients keep their permissions
after UI removal. The LuCI menu retains that historical grant, so a restricted
LuCI account should continue to receive it. New non-UI clients use `owrtpc`.
No account or broader permission is automatically provisioned.

## Mobile compatibility handshake

`owrtpc.capabilities` is an authenticated, read-only operation. Clients call it
after login and `session.access`, before reading or changing profile data. A V1
response is:

```json
{
  "api": "owrtpc-mobile",
  "major": 1,
  "minor": 6,
  "backend_version": "0.4.0-r3",
  "features": [
    "profiles.read",
    "profiles.write",
    "quick-actions",
    "device-discovery",
    "uci-apply-confirm",
    "schedule-periods",
    "device-usage",
    "profile-edit-transaction",
    "profile-create-transaction",
    "profile-delete-transaction",
    "profile-order-transaction"
  ],
  "router_date": "2026-08-28",
  "router_timezone": "Europe/Rome"
}
```

`major` changes only for incompatible contracts. A higher `minor` may add
optional fields or feature strings; clients ignore values they do not know.
`backend_version` is derived from the installed APK and is `development` for an
unpackaged source overlay. `router_date` and `router_timezone` are authoritative
for schedule presentation and day rollover; the phone clock is not.

Feature strings describe backend support, not the current session's
authorization. The client must still inspect `session.access`: a read-only
account can receive `profiles.write` in the capabilities list while its write UI
remains absent. Missing `owrtpc.capabilities`, another `api`, or an unsupported
major version is an incompatible backend rather than a generic network error.

Contract 1.1 keeps the historical `schedule` status value as the allowance
compatibility group and adds explicit `allowance_period` (`mon_thu` or
`fri_sun`) and `bedtime_period` (`sun_thu` or `fri_sat`) fields. The latter is
anchored to the evening that started an active overnight window.

Contract 1.2 adds a `devices` array to each `owrtpc.status` profile. Every
configured device is represented by its normalized `mac` and diagnostic
`used_seconds` counter. This counter explains per-device activity; the profile
counter remains authoritative for shared allowance enforcement and must not be
reconstructed by summing device counters.

Contract 1.3 adds the optional `profile-edit-transaction` feature. The
read-only `owrtpc.edit_snapshot` method returns one configuration revision and
the complete normalized profile configuration read while holding the OWRTPC
action lock. `owrtpc.profile_apply` updates one existing profile only when its
`expected_revision` still matches. A stale draft returns
`{"success":false,"code":"conflicting_edit",...}` without changing UCI.

The update request contains `section`, `name`, `enabled`, both allowance
values, all four bedtime values, `activity_threshold_bytes` (`0` selects the
router default), and the complete `devices` array. The backend canonicalizes
MAC addresses, rejects duplicates across profiles, commits only `owrtpc`,
validates the complete result and refreshes policy. If validation or policy
application fails, it restores the prior `/etc/config/owrtpc` and does not
report success. Official clients use this operation instead of generic UCI
staging for profile updates.

Contract 1.4 adds the optional `profile-create-transaction` feature and the
`owrtpc.profile_create` method. Its request is the same complete profile draft
as `profile_apply`, without `section`, and includes the snapshot's
`expected_revision`. The backend allocates the anonymous UCI section, checks
that every selected device is still unassigned, validates and applies the
complete configuration, and restores the previous file and policy on failure.
Success returns both the new `section` and configuration `revision`. Clients
must use that returned section for post-write verification and must not retry
an ambiguous create automatically.

Contract 1.5 adds `profile-delete-transaction`. `owrtpc.profile_delete` accepts
only `section` and the `expected_revision` retained from `edit_snapshot`. Clients
must ask for confirmation using that snapshot before submitting. The write ACL
is required. Missing/non-profile sections are rejected, as are stale revisions
and pending default UCI changes. Deletion shares the OWRTPC action lock and uses
an isolated UCI staging directory, validates the result and refreshes policy.

Success returns `success`, `section` and the new `revision`. The removed
profile's usage and temporary credits are cleared in memory and persisted state
under the engine lock; per-device diagnostics and other profiles are preserved.
Devices become unassigned and this profile no longer enforces restrictions on
them. If deletion fails, `apply_failed` means that both previous configuration
and policy were restored; `outcome_unknown` means restoration or final state
cleanup could not be confirmed. Clients verify absence in both the new snapshot
and live status, including an empty list after deleting the last profile. They
must never automatically retry a deletion, including after session expiry.
The action lock serializes OWRTPC operations; arbitrary external UCI writers
that ignore this lock are outside its atomicity guarantee.

Contract 1.6 adds `profile-order-transaction`. The write-only
`owrtpc.profiles_reorder` method accepts `expected_revision` and a `profiles`
array containing every current profile section ID exactly once, in the desired
order. Unknown/non-profile IDs, duplicates and omissions are rejected. An empty
array is valid only when no profiles exist. Pending default UCI changes or a
changed revision return `conflicting_edit` without committing anything.

The action lock and isolated UCI staging protect the transaction. Existing
anonymous profile IDs are persisted as explicit section names before ordering:
otherwise UCI derives new IDs from their new positions and usage can follow the
wrong profile. All profile values, counters and non-profile section positions
are preserved. Policy application is checked; `apply_failed` means the prior
configuration and policy were restored, while `outcome_unknown` requires a
fresh read because restoration could not be confirmed. The external-writer
atomicity limitation above also applies to ordering.

Success returns `success: true` and the resulting `revision`. The client must
re-read `edit_snapshot` and `status`, confirm both contain exactly the requested
order and that the snapshot revision matches the returned revision. Send once;
never replay an unknown write after transport failure or session renewal.

Quick actions commit immediately. Official mobile profile creation, editing, deletion and ordering
use the backend transactions described above; generic rpcd/UCI staging remains
available to LuCI and must not treat a successful `uci.set` as committed.
`owrtpc.refresh` applies the committed configuration. `add_time` accepts 60,
240 and the existing `all-day` value. A numeric value sets that amount of
usable time from the action's current usage, replacing any prior temporary
credit without reducing a larger unused base allowance. Bedtime and day
rollover still discard it. The historical Int32 declaration and rpcd string
coercion remain unchanged.

## Full reset (r23+)

`ubus call owrtpc reset '{"confirmation":"RESET OWRTPC"}'` is destructive and
requires an authenticated client's OWRTPC write grant through the HTTP bridge.
The root-only equivalent is `owrtpcctl reset --confirm`. Local root ubus calls
are privileged; they do not model remote ACL enforcement. A missing or different
confirmation is rejected without side effects. No paths or shell arguments are
accepted from a client.

Success is `{"success":true}` only after restoring defaults, initializing the
empty OWRTPC policy and starting the service. Failures return
`{"success":false,"error":"..."}`; a failure can occur after data deletion, so
clients must not claim the old state is intact or automatically retry after a
transport error. Check status first. No reinstall or router reboot is required.

Reset serializes with quick actions, stops the daemon and waits for its final
checkpoint, then obtains the engine lock outside the erased state directories.
It removes runtime and persistent OWRTPC state, replaces `/etc/config/owrtpc`
with the defaults shipped in the same backend APK and removes its APK config
sidecars. It reinitializes only `table inet owrtpc`, then enables/starts the
service. The initial settings are enabled with no profiles: no devices are
blocked until profiles are created. No accounting or policy algorithm changes.

Before resetting, finish/discard staged OWRTPC changes in **all** LuCI/API
sessions, wait for apply/rollback confirmation and close other editing tabs.
The backend refuses existing CLI/rpcd OWRTPC deltas or OWRTPC rollback
snapshots; it never applies, discards or confirms unrelated UCI changes.
Concurrent direct root UCI edits or firmware/package upgrades are outside this
operation's locking: do not perform them during reset. Browser-local unsaved
edits are discarded on the successful page reload.

Network/Wi-Fi/firewall UCI, DHCP leases/names, vendor aliases, passwords, keys,
installed packages, existing backups and shared system logs are untouched.
Discovered devices may still appear in the picker; only their OWRTPC profile
assignments and usage are erased. This is not secure erasure of flash media or
a router factory reset. If a broken config prevents LuCI from loading, use the
CLI after making a backup. A failure during preflight leaves data unchanged;
after destructive work begins the error must be investigated before recovery.

## Transport boundary

Local CLI/ubus calls are available with backend alone. HTTP JSON-RPC requires a
separately configured bridge such as `uhttpd-mod-ubus`, with authentication,
network restrictions and appropriate TLS. An existing LuCI installation
normally already has that bridge. OWRTPC does not install or expose it just to
prepare for mobile, and does not configure remote connectivity. The mobile app
must complete its secure credential and certificate-pairing spike before live
authentication is considered production-ready.

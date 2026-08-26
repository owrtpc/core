# Shared router API

The router component is `owrtpc/core`. Both LuCI and the future `owrtpc/mobile`
client consume the router's state and policy engine; neither duplicates it.
This document describes the existing MVP contract, not a new versioned mobile
protocol. No mobile repository, HTTP server, remote access or web filter is
created by this reorganization.

## Objects and dependencies

| API | Operations | Provider |
| --- | --- | --- |
| `owrtpc` | `status`, `validate`, `refresh`, `set_enabled`, `set_block`, `add_time`, `reset` | `owrtpc` executable rpcd plugin |
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
package is not a dependency and missing data must be tolerated. A future app
must use the same sources and precedence (alias, host hints, leases, MAC), not
assume GL.iNet firmware. No new discovery algorithm is introduced here.

## Permissions and configuration

`/usr/share/rpcd/acl.d/owrtpc.json` belongs to the backend. The stable grant is
`owrtpc`, with read-only `owrtpc` status/validation, discovery and UCI reads for
`owrtpc`, `firewall`, and optional `gl-client`. Its write grant permits the
existing quick actions and UCI changes **only to `owrtpc`**, never firewall or
vendor configuration writes.

From r23 the write grant also permits the destructive `reset` method. Read-only
accounts cannot reset. This shared permission remains installed without LuCI.

The historical `luci-app-owrtpc` grant is an equivalent compatibility alias in
that same backend file. Existing restricted clients keep their permissions
after UI removal. The LuCI menu retains that historical grant, so a restricted
LuCI account should continue to receive it. New non-UI clients use `owrtpc`.
No account or broader permission is automatically provisioned.

Quick actions commit immediately. Profile editing uses rpcd/UCI staging and
apply/confirm; do not treat a successful `uci.set` as a committed change.
`owrtpc.refresh` applies the committed configuration. `add_time` accepts 60,
240 and the existing `all-day` value (the plugin's historical Int32 declaration
and rpcd string coercion remain unchanged in this reorganization).

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
prepare for mobile, and does not configure remote connectivity. The future app
must define a versioned contract, secure credentials and certificate handling
before implementation.

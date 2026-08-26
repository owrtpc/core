# Shared router API

The router component is `owrtpc/core`. Both LuCI and the future `owrtpc/mobile`
client consume the router's state and policy engine; neither duplicates it.
This document describes the existing MVP contract, not a new versioned mobile
protocol. No mobile repository, HTTP server, remote access or web filter is
created by this reorganization.

## Objects and dependencies

| API | Operations | Provider |
| --- | --- | --- |
| `owrtpc` | `status`, `validate`, `refresh`, `set_enabled`, `set_block`, `add_time` | `owrtpc` executable rpcd plugin |
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

## Transport boundary

Local CLI/ubus calls are available with backend alone. HTTP JSON-RPC requires a
separately configured bridge such as `uhttpd-mod-ubus`, with authentication,
network restrictions and appropriate TLS. An existing LuCI installation
normally already has that bridge. OWRTPC does not install or expose it just to
prepare for mobile, and does not configure remote connectivity. The future app
must define a versioned contract, secure credentials and certificate handling
before implementation.

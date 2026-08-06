# Architecture

## Components

1. **LuCI UI** edits the `owrtpc` UCI configuration and calls the `owrtpc`
   rpcd object for live status and quick actions.
2. **rpcd plugin** exposes read-only status, validation, refresh and the
   explicit quick block action. Its ACL limits access to authenticated LuCI
   administrators granted the OWRTPC permission.
3. **owrtpcd** samples traffic periodically and asks `owrtpcctl` to reconcile
   policy.
4. **owrtpcctl** is the single policy engine. It validates assignments, accounts
   active device time, evaluates manual/bedtime/quota blocks, and atomically
   replaces the dedicated `inet owrtpc` nftables table.
5. **firewall4 include** restores the dedicated table whenever firewall4 is
   reloaded.

OWRTPC deliberately owns a separate nftables table. It does not edit generated
firewall4 chains and therefore does not depend on their internal names.

## Data model

`config globals 'main'` contains engine settings. Every `config profile`
contains:

- `name`: display name;
- `enabled`: whether the policy is enforced and accounted;
- `blocked`: explicit quick-block state;
- `weekday_daily_minutes`, `weekend_daily_minutes`: independent daily
  allowances; `0` means unlimited;
- `weekday_bedtime_start`, `weekday_bedtime_end` and their `weekend_*`
  counterparts: local `HH:MM` values; an empty pair means disabled;
- one or more `list device` values containing canonical MAC addresses.

For upgrade compatibility, the engine uses the legacy `daily_minutes`,
`bedtime_start` and `bedtime_end` values when a corresponding schedule-specific
option is absent. Saving the profile in the current LuCI UI writes the new
options.

The same normalized MAC address must not occur in two profiles. The UI and
backend both validate this invariant. If malformed configuration is written
outside LuCI, the policy engine fails closed for duplicate assignments by
blocking the duplicated MAC and reports a validation error.

## Accounting

At every sample, the engine reads the byte counters accumulated by each device
in the OWRTPC nftables table. An enabled device whose counter reached the
activity threshold adds the elapsed interval to its profile. Thus usage is the
sum of active time across all devices in that profile.

Runtime state lives in `/tmp/owrtpc`. It is checkpointed to
`/etc/owrtpc/state` at a configurable interval (15 minutes by default), trading
at most one checkpoint interval of usage after sudden power loss for lower
flash wear. A calendar-day change resets usage. All dates and bedtime rules use
the router's configured local timezone.

## Enforcement

The `inet owrtpc` table installs a forward hook before the normal firewall
filter priority. Rules first drop source MAC addresses currently blocked by any
reason, then count forwarded bytes for enabled, assigned devices. A profile is
blocked when at least one of these applies:

- manual `blocked` flag;
- current local time is in its bedtime window;
- `used_seconds >= current_schedule_daily_minutes * 60`.

Only traffic leaving through the L3 devices resolved from `monitored_network`
(by default `wan` and `wan6`) is counted and blocked. Local LAN traffic remains
available. If an installation uses different logical uplink names, they must be
set in the engine settings.
The optional `monitored_device` list bypasses logical-network resolution and is
intended primarily for containers and diagnostics.

MAC randomization or spoofing can evade MAC-based identity. Future versions can
optionally couple device identity to DHCP reservations and Wi-Fi station data.

### Flow offloading

Software or hardware flow offloading can bypass normal forward hooks after a
connection is offloaded, making time counters incomplete. The MVP therefore
requires flow offloading to be disabled in firewall settings. A later version
should detect this automatically in LuCI and offer an explicit, reversible
compatibility action rather than silently changing the router configuration.

# Architecture

## Components

1. **LuCI UI** edits the `owrtpc` UCI configuration and calls the `owrtpc`
   rpcd object for live status and quick actions.
2. **rpcd plugin** exposes read-only status, validation, refresh and the
   explicit quick block action. Its backend-owned ACL limits access to authenticated clients granted the
   OWRTPC permission, independently of LuCI. Device discovery is supplied by
   the standalone `rpcd-mod-luci` dependency.
3. **owrtpcd** samples traffic periodically and asks `owrtpcctl` to reconcile
   policy.
4. **owrtpcctl** is the single policy engine. It validates assignments, accounts
   active device time, evaluates manual/bedtime/quota blocks, and atomically
   replaces the dedicated `inet owrtpc` nftables table.
5. **firewall4 include** restores the dedicated table whenever firewall4 is
   reloaded.

OWRTPC deliberately owns a separate nftables table. It does not edit generated
firewall4 chains and therefore does not depend on their internal names.

See [API.md](API.md) for shared APIs and ACL ownership, and
[INSTALL.md](INSTALL.md) for the monolith-to-two-packages migration. The policy
engine, UCI schema and runtime/state paths are unchanged by the split.

## Data model

`config globals 'main'` contains engine settings. Every `config profile`
contains:

- `name`: display name;
- `enabled`: whether the policy is enforced and accounted;
- `blocked`: explicit quick-block state;
- `mon_thu_daily_minutes`, `fri_sun_daily_minutes`: independent daily
  allowances; `0` means unlimited;
- `sun_thu_bedtime_start`, `sun_thu_bedtime_end` and their `fri_sat_*`
  counterparts: local `HH:MM` values grouped by the evening when bedtime
  starts; an empty pair means disabled;
- one or more `list device` values containing canonical MAC addresses;
- optional `activity_threshold_bytes`, overriding the global activity threshold
  for profiles containing unusually quiet devices.

For upgrade compatibility, the engine first falls back from the explicit
period options to `weekday_*`/`weekend_*`, then to the legacy `daily_minutes`,
`bedtime_start` and `bedtime_end` values. Saving the profile in the current LuCI
UI writes the explicit period options.

The same normalized MAC address must not occur in two profiles. The UI and
backend both validate this invariant. If malformed configuration is written
outside LuCI, the policy engine fails closed for duplicate assignments by
blocking the duplicated MAC and reports a validation error.

## Accounting

At every sample, the engine reads the byte counters accumulated by each device
in the OWRTPC nftables table. Session detection runs only for enabled profiles
whose current Monday–Thursday or Friday–Sunday allowance is finite. A first interval reaching
the profile threshold (or the global 128 KiB default) creates a candidate; a
second event within five minutes confirms the session and accounts the pending
elapsed time. While active, quiet intervals remain provisional for three
minutes and are committed only if traffic resumes, which tolerates buffering
without charging the final idle tail. Unlimited profiles clear and skip all
per-device activity state. Activity remains a traffic-volume heuristic because
a router cannot observe a generic device's physical power or display state.

Every committed interval is also attributed to the originating MAC in a
per-device diagnostic counter. The sum is not used for policy decisions: quota
enforcement continues to read the cumulative profile counter only. The
owrtpcctl diagnostics command exposes attribution, activity state and the last
sample metadata. Candidate, start and stop transitions are written to the
owrtpc system log without logging every sampling interval.

Runtime usage and same-day extra-time credit live in `/tmp/owrtpc`. They are
checkpointed to `/etc/owrtpc/state` at a configurable interval (15 minutes by
default), trading at most one checkpoint interval of usage after sudden power
loss for lower flash wear. Extra credit increases only the current day's
effective limit. All Day makes that limit temporarily unlimited. Both modes are
deleted when the active bedtime window begins and at the next local
calendar-day boundary, so neither can carry into another allowance. An
overnight bedtime remains attached to the evening when it started: for example,
Saturday morning continues Friday night's Friday–Saturday window, while Sunday
evening uses the Sunday–Thursday window. All dates and bedtime rules use the
router's configured local timezone.

## Enforcement

The `inet owrtpc` table installs a forward hook before the normal firewall
filter priority. Rules first drop source MAC addresses currently blocked by any
reason, then count forwarded bytes for enabled, assigned devices. A profile is
blocked when at least one of these applies:

- manual `blocked` flag;
- current local time is in its bedtime window;
- `used_seconds >= current_allowance_period_daily_minutes * 60`.

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

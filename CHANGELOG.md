# Changelog

All notable changes to this project will be documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project intends to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.0_alpha1-r26] - 2026-08-31

### Fixed

- Numeric quick-time actions now grant the selected amount as usable time from
  current consumption instead of storing a fixed bonus relative to the daily
  allowance. Repeating `+4h`, or selecting `+1h` after `+4h`, therefore resets
  the remaining temporary time to the latest selection rather than leaving an
  already exhausted limit or accumulating both actions.
- An unused daily allowance is never shortened by a quick-time action, and
  bedtime continues to take priority over every temporary extension.
- LuCI now reports `Unlimited today` in the Remaining column while All Day is
  active instead of exposing the backend's unlimited sentinel as zero.

### Changed

- LuCI describes numeric overrides as an active temporary extension rather
  than displaying their internal persisted offset from the base allowance.

## [0.1.0_alpha1-r25] - 2026-08-31

### Changed

- Daily allowances now use explicit Monday–Thursday and Friday–Sunday periods.
- Bedtime independently uses Sunday–Thursday and Friday–Saturday nights,
  anchored to the evening when an overnight window starts.
- LuCI names every day range instead of conflating both policies under generic
  weekday/weekend labels.
- Mobile API contract 1.1 adds `schedule-periods` capability plus explicit
  `allowance_period` and `bedtime_period` status fields.

### Compatibility

- New period-specific UCI options take precedence while existing `weekday_*`,
  `weekend_*` and original unscheduled options remain supported as fallbacks.

## [0.1.0_alpha1-r24] - 2026-08-28

### Added

- Authenticated `owrtpc.capabilities` V1 handshake for the mobile client,
  including API compatibility, backend version, supported features and the
  router-authoritative date/timezone.
- Read-only ACL coverage and package, policy, smoke and lifecycle tests for the
  new capability method.

### Documentation

- Mobile application architecture, HTTPS certificate-pairing flow, JSON-RPC
  contract, read model, accessibility requirements and delivery roadmap.

## [0.1.0_alpha1-r23] - 2026-08-26

### Added

- Full OWRTPC reset on the main LuCI page, using the standard modal and
  destructive button style, typed confirmation and write-only RPC permission.
- Backend `reset` RPC and `owrtpcctl reset --confirm`: stop accounting, drain
  engine operations, clear profiles/counters/bonuses, restore shipped defaults,
  replace only OWRTPC firewall rules and restart the service without a reboot.
- Reject missing confirmation, concurrent resets, pending OWRTPC UCI changes,
  active OWRTPC rollback snapshots and symlinked state directories. Keep router
  configuration, discovery sources, signing keys, backups and system logs.
- Tests for cancellation, permissions, errors, actual headless reset and state
  not returning after a same-day service restart.

### Fixed

- Replace OWRTPC's nftables table in one atomic batch, avoiding a transient
  missing policy during reset/startup and retaining the old policy on failure.
  Generated parental-control rules and accounting decisions are unchanged.

## [0.1.0_alpha1-r22] - unreleased

### Changed

- Split the monolith into standalone `owrtpc` and optional `luci-app-owrtpc`,
  both maintained in `owrtpc/core`. The future `owrtpc/mobile` remains deferred.
- Move service, CLI, UCI, firewall integration, shared RPCs and ACLs into the
  backend without changing parental-control rules or accounting algorithms.
- Declare actual device-discovery dependencies, retain legacy ACL grants,
  and add an explicit backed-up migration from the old package owner.
- Preserve UCI as a conffile and persistent counters in the sysupgrade keep list.
- Build and verify both packages; enforce DCO and successful exact-commit CI
  before stable-key release signing. Add real APK lifecycle tests.
- Add a LuCI-generated translation template; no hand-written translations.

## Previous MVP development

### Added

- Profile-based parental-control configuration in LuCI.
- Exclusive device-to-profile assignment.
- Independent daily allowances measured cumulatively in device-minutes.
- Bedtime windows, including windows that cross midnight.
- Immediate profile block and unblock actions.
- nftables/firewall4 enforcement and periodic usage checkpoints.
- Local shell tests and an OpenWrt userspace Docker smoke-test environment.
- Separate weekday and weekend allowances and bedtime windows.
- Stable OWRTPC signing key support for individually signed APK artifacts.
- Explicit Block/Unblock action buttons in each profile row.
- Constrained device autocomplete with prefix search across friendly names,
  hostnames, IP addresses, and MAC addresses.
- Device labels enriched with LuCI host hints, including configured DHCP names.
- The autocomplete search field accepts arbitrary text without validation
  banners; only listed devices can be selected and devices assigned elsewhere
  are hidden.
- Optional GL.iNet client aliases from `/etc/config/gl-client`, with graceful
  fallback to standard OpenWrt host hints and DHCP leases.
- Mutually exclusive same-day +1h, +4h and All Day actions: the most recent choice replaces the previous one and is discarded at bedtime or day rollover.
- Profile rows show friendly device names before MAC addresses when a name is available.
- Native LuCI notifications for successful and failed profile quick actions.
- Automatic burst-aware activity sessions for time-limited profiles, including
  candidate confirmation, buffering-gap tolerance and discarded idle tails.
  Unlimited profiles skip session calculations entirely.
- A 128 KiB default activity threshold with automatic migration from the former
  1 KiB default and optional per-profile sensitivity presets.
- Per-device diagnostic usage attribution, activity-state snapshots and
  low-volume session transition logging; profile enforcement remains cumulative.
- Native LuCI time-action ComboButton and immediate Enable/Disable profile action.
- Disabled profiles now bypass bedtime, quota and manual blocking completely and
  do not reserve their devices during firewall-policy generation.
- Selecting a ComboButton time choice executes it immediately.
- Profile dialogs now use the standard LuCI staged-change workflow: Save records
  pending UCI changes, the native Unsaved Changes indicator tracks them, and
  Save & Apply commits them permanently.

### Changed

- Release builds now require a clean main checkout matching the live
  origin/main commit. Packaging uses a committed source snapshot and preserves
  checksum and source-commit sidecars without overwriting existing artifacts.
- Recover the final source changes previously distributed as r15-r20 test
  APKs; those historical binaries remain unchanged and are not retagged.

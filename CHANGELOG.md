# Changelog

All notable changes to this project will be documented in this file. The format
is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the
project intends to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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

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

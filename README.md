# OWRT Parental Control (OWRTPC)

OWRTPC is an independent, open-source parental-control application for OpenWrt
25.12 and newer. Its standalone backend uses UCI, rpcd and nftables/firewall4; an optional
LuCI package supplies the web interface.

The project is maintained under the [OWRTPC organization](https://github.com/owrtpc).
The canonical repository is
[owrtpc/core](https://github.com/owrtpc/core).

The first milestone supports:

- independent profiles;
- multiple devices per profile, with one profile at most per device;
- weekday and weekend profile allowances shared cumulatively by all devices;
- separate weekday and weekend bedtime windows, including midnight crossing;
- immediate manual block/unblock, +1h, +4h and All Day quick actions;
- replacement-based same-day extra time (+1h, +4h or All Day), discarded at bedtime or day rollover;
- native LuCI notifications for quick-action results;
- lightweight usage accounting with periodic, configurable flash checkpoints.

## Daily allowance semantics

Allowances are stored in minutes per profile, separately for Monday-Friday and
Saturday-Sunday. Usage is measured in
**device-minutes**. If two devices assigned to the same profile are active for
30 minutes at the same time, that profile consumes 60 minutes. Usage belonging
to another profile is accounted independently.

A device is considered active during a sampling interval when it transfers at
least `activity_threshold_bytes` bytes. The default is 128 KiB per sample, so
small keepalives and standby telemetry do not consume the allowance. For
profiles with a finite allowance, a first meaningful burst creates a candidate
session and a second burst within five minutes confirms it. Short buffering
gaps are counted only if traffic resumes within three minutes; otherwise the
silent tail is discarded. Unlimited profiles skip session calculations entirely.
Each profile can still override the threshold as an advanced fallback. This
remains a network-traffic heuristic: the router cannot know the physical power
or screen state of a generic client.

owrtpcctl diagnostics shows the time attributed to every configured device,
its current activity state and the most recent sampled byte count. These
per-device counters are diagnostic only: enforcement continues to use the
cumulative profile total. They are checkpointed with profile usage and reset at
the local day boundary. After upgrading from an older release, usage already
accumulated earlier that day remains unattributed until the next daily reset.

The router's local calendar selects the weekday or weekend schedule. Usage
still resets at each local calendar-day boundary, so each day receives the
allowance configured for its schedule.

## Repository layout

`owrtpc/` contains the standalone router backend package (`Makefile`, `files/`).
`luci-app-owrtpc/` contains the optional LuCI package (`Makefile`, `htdocs/`,
`root/`, `po/`). Tests, documentation and build tools are shared in this repository.
The future `owrtpc/mobile` repository is deferred; there is no separate LuCI repository.

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the design and
[docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for build and test instructions.
The [Docker environment](docker/README.md) runs the real OpenWrt 25.12.5 ARM64
userspace extracted from a sysupgrade image for UI, API and backend smoke tests.

## Installation

Install `owrtpc` first, then optionally `luci-app-owrtpc`. The interface depends
on the backend; the backend runs without LuCI. Follow [installation and manual
LuCI upload instructions](docs/INSTALL.md). Existing monolithic installations
require the documented backup/checkpoint migration before uploading r22.
See [development instructions](docs/DEVELOPMENT.md) for SDK builds, and the
[shared API contract](docs/API.md) for client dependencies and permissions.

## Project status

This is an early MVP. Test it on a non-critical router before relying on it.
MAC-address based identity is appropriate for a home-network control, but a
client that can change or spoof its MAC address can bypass it.

Firewall software/hardware flow offloading must currently be disabled so every
forwarded packet reaches the accounting hook. See the architecture notes for
details.

## Mobile app planning

A cross-platform companion app is planned, but development is deferred.
See [the mobile specifications](docs/MOBILE_APP.md) for the recorded scope.

## Contributing and security

Bug reports and focused pull requests are welcome. Read
[CONTRIBUTING.md](CONTRIBUTING.md) before submitting a change. Please report
security issues according to [SECURITY.md](SECURITY.md), not in a public issue.

## License

Licensed under the [Apache License 2.0](LICENSE).

OpenWrt and LuCI are separate projects. OWRTPC is not affiliated with or
endorsed by the OpenWrt project.

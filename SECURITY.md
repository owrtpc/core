# Security policy

## Supported versions

OWRTPC is early-stage software with a public v0.1.0 core release. Security fixes
are developed on `main` and distributed in subsequent releases; there is no
long-term support or backport commitment for older releases. Check the
[release notes](https://github.com/owrtpc/core/releases) for available fixes.
The mobile repository currently publishes source releases without installable
public app artifacts. See [the release roadmap](docs/ROADMAP.md).

## Reporting a vulnerability

Please do not disclose a suspected vulnerability in a public GitHub issue.
Use GitHub's **Report a vulnerability** form in the repository Security tab.
If private vulnerability reporting is not available, contact the maintainer
using the email address in the package Makefile.

Include the affected revision, OpenWrt release, reproduction steps and impact.
Do not include credentials, configuration backups, public IP addresses or real
device MAC addresses unless they are essential and have been redacted where
possible.

You should receive an acknowledgement within seven days. A remediation and
disclosure timeline will be agreed after the report has been reproduced and
assessed.

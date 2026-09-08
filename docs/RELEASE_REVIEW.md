# Security and OpenWrt release review

Review started 2026-09-08 for core/LuCI 0.4.0-r5 and mobile 0.4.2+19.
This is an internal engineering review, not an independent penetration test,
an OpenWrt endorsement or a guarantee that defects cannot remain. Promotion is
blocked until the remaining release gates below have evidence.

## Scope and boundaries

Reviewed the OWRTPC shell/RPC input and filesystem boundaries, UCI writes,
rpcd ACLs through both ubus and HTTP, package lifecycle, LuCI DOM construction,
mobile TLS and credential handling, native background privacy and build supply
chain. Router runtime tests use isolated OpenWrt 25.12.5 ARM64 containers with
real UCI, rpcd, procd, APK and nftables. No physical router was modified.

The threat model includes an untrusted LAN peer, an authenticated read-only
account, malformed router responses and an unprivileged local router process.
A router administrator can intentionally change policy; a compromised root OS
or phone is outside this boundary. MAC-based identification is not protection
against a client deliberately changing its MAC address. Offloading, IPv6,
clock changes, router reboot and firmware variants require release acceptance.

## Corrections and regression coverage

| Area | Change in this candidate | Evidence |
| --- | --- | --- |
| Router state | Private owned directories; refuse writable or symlinked existing paths before state access | `tests/state-security.sh`, including unchanged target files |
| Profile and quick-flag writes | Isolated UCI savedirs, checked staging/commit/application, pending-edit refusal and checked restoration | `docker/profile-write-test.sh`, real UCI plus injected commit/application failures |
| Profile text | Reject control characters before CLI/status serialization | Newline/tab requests refused without changing configuration |
| Authorization | Verify every OWRTPC write method through the HTTP ubus bridge | `docker/http-acl-test.sh`: anonymous and read-only denial; read-only status succeeds |
| LuCI text | Use text nodes for device labels, notifications, errors and version text; LuCI scalar children are interpreted as HTML | `tests/luci-text.test.js` failed on the prior source and passes with the fix |
| Mobile TLS | Enforce an existing certificate pin even if another certificate passes CA validation; invalidate pooled connections when trust changes | Real local TLS regression tests in mobile |
| Mobile network bounds | HTTPS-only credential transport, no redirects, streaming size limits and request deadline | Oversized and continuous slow responses tested |
| Mobile privacy | Android secure window and cleartext prohibition; iOS background cover | Native compilation plus pending physical acceptance |
| Supply chain | Full-history secret scan, BusyBox ShellCheck, Dart/Maven OSV scan; actions pinned by commit and scanners by digest | Mandatory CI jobs in both repositories |

Local evidence: core engine/source/release/package and LuCI text checks pass;
the unsigned r5 candidate passed all four lifecycle modes (clean, headless,
historical monolith migration and split upgrade). Later changes must rerun the
relevant checks. Mobile has 117 passing tests and a successful iOS Profile
compilation. OSV found no known vulnerabilities in 67 Dart and 53 resolved Maven
packages on the review date. The two iOS plugin Swift manifests add no remote
Swift dependency beyond Flutter and their pub-locked source. This does not scan
Apple's OS, the Flutter engine binary or the router's entire firmware.

Gitleaks found no secret in core history. Mobile's only finding was a verified,
deterministic widget-test token, now allowed by its exact value. New tokens are
not broadly excluded. ShellCheck uses the actual BusyBox dialect; SC2034 and
SC2154 are excluded because OpenWrt functions assign variables by name and
consume sourced globals. Other warnings/errors remain enabled.

## OpenWrt conformance matrix

The upstream [packages contribution rules](https://github.com/openwrt/packages/blob/master/CONTRIBUTING.md)
require declared metadata, tested dependencies, version/release discipline and
matching real-name DCO. [LuCI contribution rules](https://github.com/openwrt/luci/blob/openwrt-25.12/CONTRIBUTING.md)
cover component commits and translation workflow. These are contribution
requirements; they do not certify third-party products.

| Requirement or design principle | OWRTPC evidence | Assessment |
| --- | --- | --- |
| Standard package construction | `package.mk`, `luci.mk`, INSTALL macros, architecture-independent payloads | Implemented; inspect actual APKs in lifecycle tests |
| Full build compatibility | Pinned SDK/feeds, `sdk-build.sh --full`, normal dependency traversal and JS minification | Mandatory `full-sdk` CI gate; only successful exact-commit CI counts |
| Package boundaries | Backend owns service/config/ACLs; optional UI owns views/menu | Headless and UI-removal tests |
| Native integration | UCI, rc.common/procd, reload trigger and fw4 include; private nftables table | Container policy/reload tests; physical firmware acceptance pending |
| Preserve administrator control | No cloud account, CLI access, no forced package flags, documented migration/reset and backups | Implemented; real-device install/recovery remains pending |
| Permissions and privacy | Separate read/write grants limited to OWRTPC, local credentials, no telemetry service | Automated ACL tests; privacy/support surface and device verification pending |
| Licence and maintenance | Apache-2.0, SPDX metadata, named maintainer, contribution and private reporting policies | Present; shipped mobile third-party notices still required |
| Version and DCO | Revision increases for package changes; release resets to 1 on version changes; real-name sign-off | Rules aligned; historical nickname commits are not rewritten and need review before any upstream submission |
| Upstream feed placement | Backend uses `rpcd-mod-luci` from LuCI source feed | Valid for the documented external SDK build; not ready for submission to `openwrt/packages` without resolving its feed dependency rule |
| LuCI conventions | JS views, JSON menu, POT/translation functions and safe DOM text construction | Uses [upstream package rules](https://github.com/openwrt/luci/blob/openwrt-25.12/luci.mk); translated catalogs/Weblate and browser acceptance remain pending |
| Supported scope | Tested baseline 25.12.5/ARM64; feature/API negotiation for mobile | Do not claim every OpenWrt version, architecture or vendor firmware is certified |

No official feed submission or endorsement is claimed. The package-policies
wiki was not readable during this review; source rules above were reviewed
directly. Before an upstream submission, recheck the target repository's current
requirements and prepare focused patches rather than treating this matrix as
upstream acceptance.

## Gates before promotion

- All CI jobs green for the exact candidate commit; no unresolved high-impact
  finding, and documented disposition of every remaining review finding.
- Signed packages built from clean, pushed, DCO-signed source after CI; verify
  signatures, hashes, build metadata and all four signed lifecycle modes again.
- Cross-platform physical acceptance in mobile issue 2: all writes, conflicts,
  interrupted connections, TLS replacement, credential storage/logout,
  VoiceOver/TalkBack, both locales and enlarged text.
- Physical router acceptance: IPv4/IPv6, offloading refusal, reboot/reload,
  clock changes, interrupted writes and recovery. Directory locks can survive
  SIGKILL; crash recovery needs an explicit result before claiming resilience.
- Privacy/support and licence screens, safely redacted diagnostics, production
  signing ownership, store/beta tests and final installation/download links.
- A fresh dependency/secret scan and review of then-current OpenWrt advisories.
  Runtime system dependencies come from maintained OpenWrt firmware feeds.

Record commit, version, artifact hash, OS/firmware, test date and result in the
[release roadmap](ROADMAP.md) issues. Keep suspected unpatched vulnerabilities
out of public issues and use [private reporting](../SECURITY.md).

The [OpenWrt 25.12.5 security announcement](https://lists.openwrt.org/pipermail/openwrt-announce/2026-June/000088.html)
includes fixes in default network services, uhttpd and LuCI. The tested security
baseline is 25.12.5 with maintained package updates, not every earlier 25.12
point release. Vendor firmware needs equivalent fixes verified separately.

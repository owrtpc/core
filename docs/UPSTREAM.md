# OpenWrt contribution and independent release paths

Reviewed 2026-09-08. This is a preparation record, not an OpenWrt approval.
M3 is accepted; public release gates remain tracked in M4.

## Independent distribution

OpenWrt supports custom source feeds and separately distributed packages. An
independent OWRTPC release does not require its packages to be merged into an
OpenWrt repository first. We remain responsible for licensing, signed artifacts,
compatibility evidence, maintenance, security and truthful branding. The OWRTPC
naming/trademark question must be resolved before promotion.

Mobile store review is a separate process managed by Apple and Google. Acceptance
of a router package does not approve its companion app for either store.

## Inclusion in the OpenWrt feeds

1. Resolve naming before choosing permanent public package and app identities.
2. Confirm source-feed placement and dependencies. The normal candidate split is
   backend in `openwrt/packages`, web interface in `openwrt/luci`; OWRTPC has the
   dependency issue below, so this placement is not yet submission-ready.
3. Prepare focused pull requests against the development branches, following the
   target repository's current contribution rules. Declare licence, maintainer,
   dependencies and immutable source revision; provide SDK build/runtime evidence
   and install/upgrade/removal behavior. Use real-name matching DCO sign-offs.
4. Respond to CI and maintainer review, revise as requested and obtain merge
   acceptance. A passing local test suite does not guarantee acceptance.
5. Track the branches and architectures where builds are actually available.
   New packages are not added to existing stable release branches under the
   current packages/LuCI rules, so merge does not promise immediate availability
   on users' installed stable firmware.
6. Maintain the package and respond to defects, security reports and dependency
   changes after inclusion.

No upstream PR or message to OpenWrt maintainers has been sent. Feed inclusion
can proceed separately from our independently distributed V1 once our release
gates pass; it is not a prerequisite for that distribution channel.

## OWRTPC-specific dependency decision

`owrtpc/Makefile` currently depends on `rpcd-mod-luci`, provided by the LuCI source
feed. The `openwrt/packages` contribution rules permit dependencies only on the
OpenWrt core packages or that packages feed. Our external SDK build includes
LuCI and passes, but that does not resolve the upstream contribution rule.

The LuCI UI and mobile device discovery use `luci-rpc` host hints/DHCP leases;
removing the dependency declaration alone would risk breaking discovery.
Before preparing the submission, evaluate either:

- removing the backend's cross-feed requirement with a supported discovery API
  and compatibility tests, preserving both LuCI and mobile behavior; or
- proposing a coherent placement in the LuCI feed to its maintainers, including
  the headless backend use case. Maintainer agreement is still required.

Do not change dependencies simply to make a packaging check pass. Preserve the
optional LuCI installation, restricted ACLs, UCI transactions and local-only
control model while resolving this choice.

## Other preparation checks

- Review licence notices, immutable source archives and package metadata against
  the selected repository's current rules.
- Submit focused new commits with real-name DCO; do not rewrite public history to
  conceal older nickname sign-offs.
- Prepare LuCI translations through the project's Weblate workflow.
- Keep the documented firmware scope and final release security evidence current.
- Keep trademark clearance separate from technical review or feed acceptance.

## Primary references

- [Custom OpenWrt feeds](https://openwrt.org/docs/guide-developer/feeds)
- [Packages contribution rules](https://github.com/openwrt/packages/blob/master/CONTRIBUTING.md)
- [LuCI contribution rules](https://github.com/openwrt/luci/blob/master/CONTRIBUTING.md)
- [Trademark policy](https://openwrt.org/trademark)
- [OWRTPC conformance and release gates](RELEASE_REVIEW.md)

# Public release roadmap

Updated 2026-09-07. Implementation and release acceptance are separate: a
passing CI run or a local signed installation does not close device/store gates.

## Current baseline

- Both `owrtpc/core` and `owrtpc/mobile` are public.
- The public core release is [v0.1.0](https://github.com/owrtpc/core/releases/tag/v0.1.0).
  Later source and locally built packages are not automatically published releases.
- The [mobile source release](https://github.com/owrtpc/mobile/releases/tag/0.1.0-r1)
  has no installable Android/iOS artifact. Current source includes transactional
  profile editing, creation and deletion beyond that tag.
- M0–M2 foundations are implemented; cross-platform acceptance remains open.
- M3 functionality, including ordering, is implemented. Physical acceptance is
  still open. M4 covers public delivery.
- Core/LuCI 0.4.0-r3 signed packages have passed all four Docker lifecycle modes
  and are uploaded to a draft release. Physical acceptance and publication remain
  open in core issue 3.
- Mobile 0.4.1+18 adds Android build/signing tooling and native Linux CI validation;
  production signing identity and device/store acceptance remain open.

## Tracked work

| Milestone | Core | Mobile | Completion evidence |
| --- | --- | --- | --- |
| M3: complete profile management | [Transactional ordering](https://github.com/owrtpc/core/issues/1) | [Ordering UI and verification](https://github.com/owrtpc/mobile/issues/1), [device acceptance](https://github.com/owrtpc/mobile/issues/2) | Automated transaction/conflict tests plus recorded iOS/Android/router acceptance |
| M4: public release | [Setup/support docs](https://github.com/owrtpc/core/issues/2), [signed release](https://github.com/owrtpc/core/issues/3) | [Android builds](https://github.com/owrtpc/mobile/issues/3), [support/privacy](https://github.com/owrtpc/mobile/issues/4), [TestFlight/App Store](https://github.com/owrtpc/mobile/issues/5), [Android beta/public delivery](https://github.com/owrtpc/mobile/issues/6) | Installable signed artifacts, completed release checklist, beta results and public download/setup links |

Milestones: [core](https://github.com/owrtpc/core/milestones) and
[mobile](https://github.com/owrtpc/mobile/milestones). Issue checklists track
remaining acceptance; neither milestone has a committed delivery date.

## Execution order

1. Accept transactional ordering across the API and both mobile platforms
   (implementation and automated checks complete; physical acceptance open).
2. Complete reproducible Android builds/signing and iOS distribution preparation.
3. Complete setup/support/privacy surfaces and physical-device acceptance.
4. Run TestFlight and closed Android testing; resolve release-blocking findings.
5. Publish compatible core/mobile releases and installation instructions.

Core/LuCI can be released before mobile store delivery once its own gates pass.
Use [DEVELOPMENT.md](DEVELOPMENT.md) for mandatory commit/CI/sign/build ordering.
An APK in `dist/` is evidence of a local build, not of public publication or
physical-router acceptance.

## Release acceptance record

Record source SHA, artifact version/build, platform/OS, router firmware/model,
test date, outcome and any linked defect in the relevant issue. Leave tests
pending until performed. Required scenarios are listed in
[MOBILE_APP.md](MOBILE_APP.md#manual-release-gates).

External dependencies include production signing ownership, store accounts,
physical Android/iOS devices, a supported router and beta participants. Never
record a store submission, signing setup or device test as complete solely
because shared Flutter checks passed.

[Mobile setup](MOBILE_SETUP.md) covers HTTPS, certificate fingerprint comparison,
restricted accounts, flow offloading and feature-based compatibility. Release
publication must also supply the final download links and device acceptance record.

V1 remains one local router, English/Italian and no cloud. Notifications,
multi-router support and history remain deferred. An OpenWrt feed is not
required; optional F-Droid or signed GitHub Android distribution needs a recorded
owner decision.

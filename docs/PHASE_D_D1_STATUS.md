# Phase D Historical Status — D1 Foundation / Early D2 Progress

> **HISTORICAL SNAPSHOT — NOT CURRENT PHASE STATUS**
>
> This file preserves the state of Phase D when D1 had completed and D2.1 was the
> newest implemented Newsreader milestone. Statements below such as "D2 is in
> progress" and "next step is D2.2" describe that historical point in time and
> must not be used to determine the current implementation status.
>
> Current Phase-D status and binding architecture live in
> `PHASE_D_NATIVE_IOS_IPADOS.md` and `ARCHITECTURE_DECISIONS.md`.

Historical status at this snapshot: **D1 COMPLETE AND FROZEN FOR CONTINUED DEVELOPMENT**

This document records the implementation status of the early Phase-D work.

## D1 — Foundation / Safe Replacement

D1 is complete and frozen for continued development.

### D1.1 — Apple workspace restructure

Complete.

- Apple platform code is organized under `apple/`.
- macOS lives under `apple/macos/`.
- iOS lives under `apple/ios/`.
- Apple-shared Swift code lives under `apple/shared/FluxApple/` and is extracted only on first real reuse.

### D1.2a — Apple UniFFI packaging

Complete.

- Canonical packaging is owned by `apple/Build/build-uniffi.sh`.
- iOS consumes UniFFI through an embedded `FluxUniFFI.framework` inside the generated XCFramework packaging rather than a standalone embedded Rust dylib.
- macOS continues to use its working native packaging path.
- The repaired iOS packaging was successfully delivered through Apple Transporter without the earlier `Invalid Swift Support` rejection.

### D1.2b — Minimal native iOS/iPadOS shell

Complete.

- One native iPhone/iPad application target exists under `apple/ios/`.
- Normal native development uses the separate development identity `dev.kevincfechtel.fluxNews.nativeDev`.
- The shell initializes the real Rust Core with native sandbox paths and exposes diagnostic/runtime-health state.
- iPhone and iPad simulator execution has been validated.

### D1.3 — Production replacement and legacy migration feasibility

Complete for continued development.

The production-identity Upgrade Test was installed over the existing Flutter application in the iOS simulator without uninstalling it first. The Flutter `Runner.app` bundle was replaced by the native `FluxNews.app`, while the native read-only legacy discovery could still observe meaningful persisted Flutter state.

Observed migration-feasibility evidence included:

- API key present.
- Base URL present.
- production identity accessible.
- Keychain credentials accessible.
- App Group accessible.
- feed preferences present.
- legacy database detected.
- legacy cache detected.
- download metadata detected.
- legacy downloaded media files detected.

Zero counts for compatible settings, custom headers, or playback progress are not treated as failures unless the source fixture is known to contain such data.

The D1.3 probe is discovery-only: it does not import or modify legacy state. Actual migration remains Phase D9.

The simulator used for this successful in-place replacement test should be preserved where practical as a useful D9 migration fixture.

A physical-device production-upgrade smoke test remains required before final production replacement/release because signing, Keychain/App Group behavior, and App Store update semantics must ultimately be confirmed on real hardware. This is a release-readiness requirement, not a blocker for continued D2 development.

## D2 — Native Newsreader Foundation

Phase D2 is in progress.

### D2.1 — Shared Newsreader primitives + minimal iOS Newsreader store

Complete.

The implementation established the first real Apple-shared Newsreader presentation primitives and a focused iOS-specific Newsreader store without creating a second domain layer or porting the macOS `BrowserStore` wholesale.

Validation completed successfully:

- Rust tests: **188 passed**.
- iOS simulator build: **passed**.
- iOS tests: **2 passed**.
- macOS application build: **passed**.
- macOS tests: **124 run, 122 passed**.
- `git diff --check`: **passed**.

The two macOS test failures are the pre-existing locale-sensitive notification tests and are not D2.1 regressions:

- `SystemNotificationPresentationTests.testBodyIncludesPluralCountAndLocalizedDateTime`
- `SystemNotificationPresentationTests.testBodyPreservesSingularCount`

No new Rust Core or UniFFI contract change was required for D2.1.

### Next

The next implementation step is D2.2: native iPhone/iPad navigation and the real Article List foundation. D2.2 should continue using the existing Core contracts and the shared primitives introduced by D2.1, without prematurely implementing Reader/Search or later background/media/system-integration phases.

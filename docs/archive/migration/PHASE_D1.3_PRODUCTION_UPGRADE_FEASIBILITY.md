# Phase D1.3: Production Upgrade Feasibility

> **Status: HISTORICAL FEASIBILITY PROOF — FINAL D9 PRODUCTION UPGRADE ACCEPTED 10 OCTOBER 2026**
>
> This document preserves the original feasibility/probe contract. The final
> productive Flutter-to-native TestFlight upgrade was later accepted under D9;
> current migration behavior and acceptance status live in
> `IOS_D9_FLUTTER_REPLACEMENT_COMPLETION.md` and
> `PHASE_D_NATIVE_IOS_IPADOS.md`.

## Verified legacy contract

The historical FluxNews revision `8f8161787d99b6bedb3d17404bb370b53c869aae`
defines the production identity as `dev.kevincfechtel.fluxNews`. Its iOS
entitlements declare `group.dev.kevincfechtel.fluxNews` and
`com.apple.developer.carplay-audio`. The URL scheme is `fluxnews`.

The repository does not contain the Flutter project itself. The historical
source audit therefore proves storage names and code paths, but not the state
of a particular installed user's device.

## Configurations

`FluxNews` remains the normal native development scheme. It uses the existing
`dev.kevincfechtel.fluxNews.nativeDev` Bundle ID, has no production App Group
entitlement, and stores Core data under `FluxNewsNativeDev`.

`FluxNewsUpgradeTest` uses the `Upgrade Test` build configuration. It uses the
existing production Bundle ID and the verified App Group/CarPlay entitlements.
Its Rust Core data is deliberately separate under `FluxNewsNativeUpgradeTest`.
It is not an App Store upload configuration and requires a matching signed
development profile before device installation.

## Read-only probe

`LegacyStateDiscovery` performs no writes. It reads Keychain attributes only,
checks App Group access, checks file existence/counts, and reads file metadata.
It does not open SQLite, modify UserDefaults, read secret values, move/delete
files, or initialize Core from legacy paths.

| Category | Proven source | Probe result |
| --- | --- | --- |
| Account | Flutter secure storage, service `flutter_secure_storage_service`, keys `minifluxURL` and `minifluxAPIKey` | Presence only; values never displayed |
| Custom headers | Secure-storage keys with `customHeadersKey_` / `customHeadersValue_` prefixes | Key count only |
| Compatible settings | Secure-storage keys including `useBlackMode`, sync, truncation, and audio settings | Count of known current-equivalent keys |
| Feed preferences | Secure-storage key `feedSettingsOverrides` | Presence only |
| Playback progress | Secure-storage keys prefixed `audio_progress_` | Count only |
| Download metadata | Secure-storage path/timestamp/title/feed-title prefixes | Count only |
| Download files | Application Support `audio_cache`, files prefixed `audio_` | File count only; no adoption |
| Legacy database | Library `news_database.db` | Existence only; never opened |
| Legacy cache | Library `Caches` | Read-only file presence |

The App Group and Keychain results require the production identity, valid
entitlements, and a physical installation containing legacy state. The
nativeDev build should report them unavailable because it intentionally uses a
different identity.

## Physical upgrade procedure

1. Install or use the current Flutter FluxNews production/TestFlight build on
   a physical iPhone.
2. Configure an account, a current setting, one feed preference, podcast
   playback progress, and a downloaded audio item where practical.
3. Record the expected categories without recording secret values.
4. Install the signed native `FluxNewsUpgradeTest` build over the Flutter app;
   do not delete the Flutter app first.
5. Launch it and verify the diagnostic discovery section reports the expected
   identity, App Group, Keychain presence, settings, progress, downloads, and
   database/cache detection.
6. Verify Core paths use `FluxNewsNativeUpgradeTest`, not `Library/news_database.db`
   or `audio_cache`.
7. Compare the legacy files and database timestamps/content after the run.
   The probe must not have moved, renamed, deleted, or rewritten them.

This procedure has not been executed in the available environment. Simulator
launches prove only the native shell and Core behavior, not production App
Group/Keychain access or an update over Flutter.

## Repeating migration tests later

Application deletion does not reliably remove Keychain items. App Group data
may remain while another group member is installed. Reinstalling Flutter may
also create a new database rather than reproduce the original state. D9/D10
tests should preserve a device backup/fixture, explicitly inspect and reset
Keychain/App Group state, and clear the new `FluxNewsNativeUpgradeTest` Core
directory between repetitions. No migration marker or reset tool exists in
D1.3.

## Native iOS developer commands

The iOS developer scripts use the shared Apple UniFFI package and repository-local
DerivedData under `.build/DerivedData`:

```bash
apple/ios/Build/build-app.sh
apple/ios/Build/run-simulator.sh
apple/ios/Build/test.sh
```

Use `--configuration "Upgrade Test"` with `build-app.sh` to compile the
production-identity feasibility build. Installing that build over the Flutter
application is an explicit migration validation operation, not normal development.
The macOS scripts under `apple/macos/Build/` and these iOS scripts all ultimately
use `apple/Build/build-uniffi.sh`; macOS additionally stages its generated Swift
files and embeds the macOS library for its app target.

## Versioned iOS builds (aligned with Android)

The iOS `build-app.sh` and `archive.sh` scripts accept the same positional
`variant buildNumber versionName` pattern as Android. Both use
`apple/ios/Build/versioning.sh` for validation and pass Xcode build-setting
overrides rather than rewriting source `Info.plist` files. The app and widget
both resolve `CFBundleShortVersionString` from `MARKETING_VERSION` and
`CFBundleVersion` from `CURRENT_PROJECT_VERSION`.

```bash
# Build an installable production-identity upgrade test:
./apple/ios/Build/build-app.sh productionRelease 3001 3.0.0 --destination 'generic/platform=iOS'

# Create a signed archive with the production Flutter bundle identity:
./apple/ios/Build/archive.sh productionRelease 3001 3.0.0

# Parallel nativeDev application/archive:
./apple/ios/Build/build-app.sh developmentRelease 3001 3.0.0 --destination 'generic/platform=iOS'
./apple/ios/Build/archive.sh developmentRelease 3001 3.0.0
```

The iOS build scripts accept positive decimal build numbers, including the existing
Flutter production scheme (e.g. `2026092601` from `FluxNews/pubspec.yaml`).
App Store Connect remains authoritative for upload acceptance. Build number
`3001` is only an example and may be older than the installed Flutter build;
for a production in-place upgrade prefer the next unused higher value, such as
`2026101001`. The existing `--configuration`, `--build-number` and new
`--version-name` flags remain usable. `Upgrade Test` still targets the
production Flutter identity only for on-device migration validation, not
automatic production App Store upload.

## Transporter / TestFlight distribution

Both archive identities can now be exported through the same guarded script.
The export does not submit the app for review, upload the IPA, or publish a
release. Transporter uploads the resulting local IPA to App Store Connect;
use an internal TestFlight tester to validate the production Flutter upgrade.

```bash
# Existing Flutter production bundle ID, for a true in-place TestFlight upgrade:
./apple/ios/Build/archive.sh productionRelease 3001 3.0.0
./apple/ios/Build/export-appstore.sh productionRelease
# IPA: dist/ProductionExport/*.ipa

# Separately installable development identity:
./apple/ios/Build/archive.sh developmentRelease 3001 3.0.0
./apple/ios/Build/export-appstore.sh developmentRelease
# IPA: dist/TestFlightExport/*.ipa
```

Omitting the export variant remains backward compatible with NativeDev.
The `--archive` and `--export-path` overrides remain supported for both
identities, but the script refuses archives or exported IPAs whose app/widget
Bundle IDs, display names or build/version numbers do not match their expected
identity. It also checks the archived app and widget signatures and App Group
entitlements before export. Export uses an App Store Connect distribution
method with automatic signing and the configured Apple Developer team; matching
distribution certificates/profiles, approved entitlements, and App Store Connect
permissions are required.

For migration acceptance, install the TestFlight version **over** an existing
Flutter production installation without deleting the app. This release route
is intended for TestFlight validation; public App Store rollout still requires
separate review and release decisions.

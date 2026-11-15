# Phase E — Native Android

> **Status: E1 THROUGH E9 COMPLETE / REAL-DEVICE ACCEPTED — PRODUCTION FLUTTER→NATIVE UPGRADE AND PLAYBACK VERIFICATION V2 ACCEPTED**
>
> Repository-first audit baseline: main at 558d883cc88a966e3e6abc8e39adffdbb18cd1eb (28 September 2026); current closure work is recorded on `phase-e9-flutter-replacement` in October 2026.
>
> Phase A, Phase B and Phase C are complete and architecture-frozen. Phase D implementation and the physical Flutter-to-native iOS production upgrade are complete/accepted as of 10 October 2026. Phase E replacement implementation and migration acceptance are also complete; Android CI #486 is green and the later shared Apple gate is green on main (Apple #123, attempt 2). Remaining Play/F-Droid work is distribution, not E9 implementation acceptance. The follow-up release plan, including a native F-Droid build/publish action and unified cross-platform release scripting, is authoritative in [RELEASE_DISTRIBUTION.md](RELEASE_DISTRIBUTION.md).
>
> Post-completion structural cleanup was merged on 11 October 2026. The large
> `AndroidArticleTimeline.kt` and `AdaptiveAppShell.kt` sources were split into
> focused Timeline, row, shell, model/policy and navigation files without changing
> Compose lifecycle, Timeline/store ownership, paging, Scrollover, navigation,
> Core/UniFFI, persistence or migration semantics. Baseline and Startup Profiles
> were regenerated with the canonical generator after the Kotlin top-level moves.
> PR #30 passed Android CI #487 before merge.
>
> This document is the authoritative implementation contract for the native Android replacement. ARCHITECTURE_DECISIONS.md remains the primary architecture authority and MOBILE_PRODUCT_SEMANTICS.md remains the shared native-mobile product contract. Where this document describes Android mechanisms, those mechanisms implement the shared contracts rather than redefining the product domain.

## 1. Goal and non-goals

Phase E replaces the existing Flutter Android client with a first-class native Kotlin Android client over the existing Rust Core and UniFFI boundary.

> **Status-reading note:** E1-E7 sections preserve milestone-local wording from
> the dates when later physical proofs were still deferred. The E9 section and
> document header are authoritative for current replacement status; completed
> E9 production-upgrade evidence supersedes those historical "pending/deferred"
> statements.

The target is not a Kotlin rewrite of Flux domain logic and not a visual copy of the iOS application.

Phase E must:

- preserve the existing production Android product identity and provide a safe Flutter-to-native upgrade;
- use the current Rust Core as the durable authority for all already Core-owned state and rules;
- use Kotlin and native Android APIs for presentation, lifecycle and OS integration;
- preserve the completed native-mobile product semantics from Phase D where they are platform-independent;
- adapt navigation, layout, gestures, widgets, background work, media and automotive integration to Android conventions;
- measure Android performance on real Android hardware before introducing renderer-specific complexity.

Phase E must not:

- create a second domain, Miniflux, persistence, sync, search or media-policy layer in Kotlin;
- copy SwiftUI, UIKit, BGTaskScheduler, WidgetKit, AVFoundation, CarPlay or Apple scene/lifecycle mechanics;
- make the legacy Flutter database, secure-storage schema, widget snapshot or media cache a permanent runtime API;
- reintroduce Flutter behavior that Phase D deliberately retired or replaced;
- reopen architecture-frozen Phase A-D decisions without a concrete technical contradiction;
- introduce a custom JNI/C/JSON bridge around Core. UniFFI is the selected native binding technology.

## 2. Repository audit result

At the audit baseline there is no native Android client directory in Flux. The repository contains:

- core/ — the shared Rust workspace;
- core/crates/flux-core — durable domain, storage, networking, sync, article, widget, notification and media implementation;
- core/crates/flux-uniffi — the typed UniFFI surface;
- apple/macos, apple/ios and apple/shared — completed native Apple clients/integration;
- docs — the frozen architecture and phase contracts.

Android preparation therefore exists primarily in the shared architecture and Core, not in a partially implemented Kotlin application.

The current Core/UniFFI surface already covers the feature-domain baseline required by Android, including article queries/counts/catalog, search, Reader/article processing, read/star mutations, cooperative sync cancellation, feed preferences, notification candidates, widget projections, configuration snapshot/backup, Listening List, playback preparation/progress, media downloads/policies/retention and legacy playback import.

The current configuration-backup model already includes Android as a platform value.

The current Rust workspace builds flux-uniffi as a cdylib/lib and includes the UniFFI binding generator, but the repository does not yet contain:

- Android Rust target build tasks;
- generated Kotlin binding integration;
- Gradle/AGP packaging of libflux_uniffi for Android ABIs;
- Android runtime initialization for the current Rust TLS platform-verifier integration;
- Android Core lifecycle/execution adapters;
- an Android test/build/release pipeline.

Those are E1 integration responsibilities, not evidence that the Core domain should be rewritten.

### 2.1 Core/UniFFI readiness assessment

**Domain readiness: high.** No release-baseline Android product-domain gap was found in the repository-first audit.

**Binding/API readiness: high, subject to an Android compile/runtime proof.** The existing typed UniFFI API is deliberately platform-neutral, but it has so far been exercised by Apple clients.

**Android build/runtime readiness: not yet proven.** E1 must validate the current pinned UniFFI version, Android ABI packaging, Kotlin bindings, synchronous-call execution policy and TLS verifier initialization before product implementation proceeds.

A concrete Android blocker may justify a narrow shared Core/UniFFI fix. It does not justify a Kotlin domain duplicate.

## 3. Authority and ownership

### Rust Core owns

The existing architecture remains authoritative for:

- domain models and stable identities;
- Miniflux networking and custom-header application;
- SQLite persistence and migrations;
- sync, reconciliation, freshness and cooperative cancellation;
- offline read/unread/star and other durable mutations;
- article/Reader processing and search;
- navigation catalog/count projections;
- feed preferences;
- notification candidates and acknowledgement semantics;
- widget projection/domain data;
- configuration snapshot and encrypted backup format;
- media/enclosure/Saved Media/Listening List domain;
- playback progress and reconciliation;
- download intent/state, policies, retention and downloaded-data summary;
- all other existing platform-independent rules.

### Native Android owns

Kotlin/native Android owns:

- Compose/UI presentation and navigation;
- adaptive phone/tablet/foldable layout;
- visible list snapshots, scroll state and gestures;
- lifecycle and process integration;
- credentials and platform-local presentation preferences;
- browser/share integration;
- WorkManager/background execution;
- NotificationManager delivery and runtime permission UX;
- home-screen widget presentation/configuration;
- runtime media playback, audio focus and foreground media service;
- physical transfer execution and transfer registry;
- MediaSession/system controls/Android Auto;
- OS file/share pickers and support-log presentation;
- release identity/signing and Android packaging.

Native Android may maintain bounded presentation/runtime state. It may not become a second durable domain authority.

## 4. Kotlin, Compose and adaptive UI baseline

Kotlin is the native Android language baseline.

Jetpack Compose is the default UI toolkit. The Article Timeline starts with Compose, using a lazy native list and stable Article IDs. Do not introduce RecyclerView pre-emptively because iOS eventually required UIKit.

Material 3 adaptive/window-size/posture APIs should be used where they provide the appropriate native behavior for phones, tablets and foldables. Layout decisions are based on available window environment, not device model names.

The initial shell should be one adaptive app rather than separate phone/tablet/foldable implementations. Compact environments may use native transient navigation; wider environments may keep navigation and the Article List visible concurrently. Exact Android presentation is selected during E2 from current platform APIs and device testing.

Compose ViewModels/state holders own presentation state only. They do not own a second Core, a second sync state machine or durable article/media state.

## 5. Android Core runtime and synchronous execution

There is exactly one active Core/account session per app process.

A process/app-scoped Android runtime owns the active Flux UniFFI object, Core event subscription, synchronization coordination and media runtime attachment. Activities, Composables, Navigation destinations, widgets and services attach to that runtime according to lifecycle; they do not independently create Core instances against the same storage.

The Rust/UniFFI API is synchronous. Potentially blocking Core calls must never execute on the Android main thread.

Android must provide a small bounded execution policy for synchronous Core work. It should distinguish responsive/local work from potentially blocking remote/network work sufficiently to prevent remote work from head-of-line blocking presentation-critical local reads, while respecting Core's own storage/sync serialization. Kotlin coroutine cancellation alone is not proof that a synchronous Rust call was cancelled; cancellable Sync must use the existing Core SyncCancellation contract.

Process death is normal on Android. Durable intent belongs in Core; native runtime state must be reconstructable on app/service restart.

## 6. Rust/UniFFI Android build contract

E1 must produce a deterministic Gradle-integrated build for the existing flux-uniffi crate and generated Kotlin bindings.

Required properties:

- generated bindings are build products and are not manually edited;
- Android shared libraries are built from the existing Rust workspace;
- Gradle packages the correct library per supported ABI;
- Debug and Release paths are reproducible from repository scripts/tasks;
- Kotlin calls only the generated UniFFI API, with no handwritten parallel JNI API;
- symbol/library loading is deterministic and tested before first Core call;
- Core Rust tests remain platform-neutral and unchanged unless a concrete Android gap requires an additive fix.

Minimum E1-B ABI/runtime validation:

- arm64-v8a runtime on the API 29 compatibility floor;
- arm64-v8a runtime on a contemporary Android emulator, including the current 16 KB page-size path where available;
- x86_64 cross-build and APK packaging.

At this E1 checkpoint the physical arm64-v8a runtime smoke was deliberately deferred until the native app became meaningfully testable. That runtime requirement was later superseded by the stronger E9 productive physical-device upgrade acceptance, which exercised the packaged UniFFI/Core path in the real replacement app. The targeted E1-B smoke script remains useful as a diagnostic but is no longer a separate release blocker.

The legacy production app also advertises armeabi-v7a. Whether Phase E continues 32-bit ARM support is an explicit E1 distribution compatibility decision. If it is retained, the current pinned UniFFI/JNA path must pass real ARM32 validation before release. Do not upgrade UniFFI or another shared dependency solely speculatively; a concrete Android blocker must be demonstrated and all affected Rust/Apple gates must remain green after any shared upgrade.

## 7. Android TLS and Miniflux transport

Miniflux networking remains in Rust. Android must not introduce a Kotlin HTTP client for Miniflux.

The current Core uses rustls with the platform-verifier integration. E1 must prove the Android initialization and trust behavior of the pinned repository version before account UI work proceeds.

The transport gate must cover at least:

- normal public/system CA trust;
- rejection of invalid certificates;
- the production-required behavior for user-installed CA trust, because the legacy Android client explicitly trusted both system and user anchors;
- custom HTTP headers;
- HTTP and HTTPS account URLs.

Plain HTTP remains supported where the existing account validation permits it. Android presents the same visible insecure-HTTP warning as the native iOS product; the warning does not create a second transport policy.

If the existing platform verifier requires a narrow Android initialization hook through the UniFFI/native integration, adding that hook is permitted. Replacing Core networking with Kotlin networking is not.

## 8. Android identities, signing and migration safety

### 8.1 Production identity

The current Flutter Android production application ID is:

    de.circle_dev.flux_news

The native production replacement must retain that application ID and must be signed with the signing identity required for an in-place update of the installed production application.

Changing Kotlin namespace/source package is a separate implementation choice, but it must not accidentally change the production application ID or break durable Android component identity that must survive the upgrade.

The current Flutter production minimum SDK is 29. Phase E keeps API 29 as the initial compatibility floor unless E1 discovers a concrete native dependency that cannot support it and a deliberate release decision changes the floor. Raising it casually would strand existing installed users.

### 8.2 Development identity

Normal native development uses a separate application ID and sandbox so the Flutter production app and native development app can coexist on one device.

The development identity must never be treated as proof that production legacy data is accessible. Migration acceptance requires a production-identity build signed for the real update path.

### 8.3 Migration contract

Android legacy migration is copy/import-only, idempotent, restart-safe and non-destructive.

The native app may read compatible legacy state, then writes imported state into the new native/Core-owned stores. It must not:

- operate directly on the Flutter SQLite database as its Core database;
- continue using Flutter secure storage as the normal credential/preferences store;
- keep the Flutter widget snapshot as the native widget domain;
- use legacy media filenames/cache metadata as the new durable media identity;
- delete legacy data merely because an import completed.

Existing valid native/Core state wins over legacy state.

Migration completion belongs to the native Android migration coordinator because only that coordinator can know whether all Android-owned legacy sources were evaluated successfully.

## 9. Proven legacy Android sources

The current FluxNews Flutter repository is evidence for migration and Android-specific historical behavior only.

At the audit baseline its production Android state includes:

- application ID de.circle_dev.flux_news;
- minimum SDK 29;
- SQLite database news_database.db, schema version 12;
- flutter_secure_storage backed by Android Keystore configuration;
- SharedPreferences playback progress using audio_progress_<newsID>;
- app-support files under the application private files area;
- downloaded audio under audio_cache;
- widget projection in HomeWidgetPreferences SharedPreferences;
- WorkManager-based background sync;
- an Android media browser/audio service for Android Auto;
- cleartext HTTP allowed and system plus user certificate anchors trusted.

The established media migration contract in PHASE_B9_AUTOMOTIVE_AND_MIGRATION.md remains authoritative:

- article/enclosure identity comes from the legacy database;
- article-keyed playback progress imports only when exactly one audio enclosure resolves;
- ambiguity is skipped and reported, never guessed;
- explicit legacy zero does not become Completed or resumable InProgress;
- positive progress may import through import_legacy_playback;
- existing Core playback wins;
- downloaded files are verified by the native adapter, resolved to the canonical enclosure and finalized through the Core download operation;
- migration never deletes legacy state.

D9 iOS migration decisions that express product semantics also apply to Android where the same legacy value exists, including:

- native presence wins;
- background-sync interval values migrate only to the native mobile on/off semantic, not to a user-controlled scheduler interval;
- autoDownloadAudioAfterSync maps to the Core Listening List auto-download preference rather than restoring the old sync-triggered implementation;
- syncReadStatusImmediately is not mapped to the broader Core DeliveryMode;
- legacy feed overrides import only when they have a current semantic equivalent;
- serialized zero defaults are not evidence of an explicit false decision when the Flutter storage format cannot distinguish them;
- obsolete Flutter-only appearance/layout/cache options are dropped.

Exact extraction from flutter_secure_storage is an E1 migration-feasibility gate. The new runtime must not take a long-term dependency on the Flutter plugin.

## 10. Credentials, preferences and Android backup

### Credentials

Account URL, API key and sensitive custom configuration use an Android Keystore-backed native credential design.

Do not introduce deprecated AndroidX encrypted-preferences APIs as the new long-term store merely to resemble the Flutter implementation. E1 must select and test a small app-private encrypted credential envelope whose encryption key is protected by Android Keystore, or another current Android-native equivalent with the same security properties.

The legacy flutter_secure_storage reader is a one-time compatibility adapter only.

### Non-secret presentation preferences

Platform-local non-secret Android preferences should use the current Android native preference/data-store approach and remain separate from Core-owned settings.

### Android system backup

OS backup/device-transfer must be explicit and conservative.

Do not automatically back up:

- the Core database;
- raw API credentials;
- downloaded media;
- runtime transfer state;
- support logs;
- widget projection/cache state.

If Android automatic backup is retained, only deliberately selected non-sensitive or already encrypted configuration artifacts may participate. Config Backup/Restore remains the product's explicit encrypted configuration handoff and is not an article/media backup.

## 11. Shared mobile product baseline

MOBILE_PRODUCT_SEMANTICS.md is the source of truth for behavior shared by iOS/iPadOS and Android.

Android must preserve at least:

- All News / Starred / Category / Feed scope semantics;
- transient Unread/All and sort direction;
- Compact / Visual / Visual Compact article presentation semantics;
- Miniflux reading time projected from Core;
- absolute/relative publication-time preference;
- feed metadata above the headline and publication/reading-time row behavior;
- Reader/original-link/feed-specific routing semantics;
- Mark as Read on Scrollover behavioral contract;
- read/unread and star/unstar optimistic Core mutations;
- configurable semantic swipe actions with zero, one or two actions per side;
- scope-level Mark All as Read and Mark All as Read & Next;
- semantic Article List actions and overflow access;
- Search;
- Manual Sync and cooperative cancellation;
- Background Sync on/off semantics;
- feed preferences;
- Listening List and shared media-domain semantics;
- per-feed System Notifications;
- per-widget scope/read-filter/sort semantics;
- configuration backup/restore capability;
- localization baseline;
- account/version/HTTP-warning/About surfaces;
- support diagnostics/logging behavior.

Android may express each behavior with different native chrome, navigation or gestures.

## 12. E1 — Android Foundation & Production Migration Spike

E1 is the next implementation step.

### E1-A — Project skeleton

Create android/ with the minimum native application structure, Kotlin and Compose baseline, Gradle wrapper/build, development identity and a production-identity configuration path.

Implemented on 28 September 2026 with Android SDK API 36, AGP 8.9.2, Kotlin/Compose compiler 2.0.21, and a Compose Material 3 baseline. `android/Build/build-app.sh` and `android/Build/test.sh` are the canonical Android build and validation entry points.

Do not begin product UI beyond what is required to prove startup/runtime.

### E1-B — Rust/UniFFI build and smoke test

E1-B is complete. E1-B1 implements `android/Build/build-uniffi.sh`, which builds and verifies the existing `flux-uniffi` cdylib for `arm64-v8a` (`aarch64-linux-android`) and `x86_64` (`x86_64-linux-android`) in Debug and Release modes. E1-B2a resolves the minimal Kotlin-safe UniFFI surface naming while retaining UniFFI 0.29 and the unchanged Core domain. E1-B2 generates Kotlin bindings, compiles them with JNA 5.13.0 and packages variant-specific native libraries. Its crate-local `uniffi.toml` uses the official UniFFI 0.29 Android configuration with `disable_java_cleaner = true`, retaining minSdk 29 through the generated JNA Cleaner fallback without a Lint suppression. E1-B3 adds a `developmentDebug`-only Android instrumentation smoke test for library loading, Flux/Core construction, a local query, typed error propagation, and event-subscription cleanup; `android/Build/test-uniffi-runtime.sh` selects one explicit device and runs only that test target.

Runtime acceptance on 28 September 2026 passed the same three-test suite on an API 29 / Android 10 `arm64-v8a` emulator with 4 KB pages and on an API 37 `arm64-v8a` emulator with 16 KB pages. Both runs completed 3/3 tests successfully, proving the generated Kotlin/JNA/UniFFI path, native library loading, Flux/Core construction, local SQLite-backed querying, typed Rust-to-Kotlin error propagation and event-subscription cleanup across the compatibility floor and a contemporary 16 KB-page runtime. The `x86_64` path remains cross-build/APK-package validated. The later E9 productive physical-device upgrade acceptance additionally proved the packaged native/Core runtime on real replacement hardware; a separate E1-B physical smoke is no longer an outstanding release gate.

Prove:

- Rust Android targets;
- Kotlin binding generation;
- native library packaging/loading;
- Flux/Core construction;
- a minimal local Core query;
- typed error propagation;
- Core event subscription/cleanup;
- Debug and Release build paths.

### E1-C — TLS/account transport proof

E1-C is complete. The pinned `rustls-platform-verifier` 0.5.3 is now the Android TLS verifier for the Core transport. `flux-core` declares it for `cfg(target_os = "android")` next to the existing Apple target and applies it through one shared `platform_tls_config()`; Apple keeps its previous semantics unchanged and every other target keeps the `ureq` default. Without this the Android build fell back to `rustls-native-certs`, which probes Unix trust-store paths that do not exist on Android and therefore resolved an empty root store.

The verifier needs JVM handles before the first Rust TLS handshake, so `flux-uniffi` exposes the narrow Android initialization hook this contract permits: a single JNI entry point that hands over the JVM, the application `Context` and the class loader and carries no domain, Miniflux or Core surface. Kotlin calls it once from `Application.onCreate` through `AndroidPlatformTrust`, which is idempotent for the process; the underlying crate initialization is idempotent as well. The Kotlin verifier component is resolved from the `rustls-platform-verifier-android` crate that `core/Cargo.lock` already selects — Gradle reads both the on-disk Maven repository and the component version from `cargo metadata`, so the AAR can never drift from the crate. R8 keep rules cover the JNI-reached verifier classes and the bootstrap entry point.

Miniflux networking stays entirely in Rust/`ureq`; no Kotlin HTTP client exists. The app declares `INTERNET` and a network security configuration that preserves the legacy Android product policy of permitted cleartext HTTP plus system and user certificate anchors.

Proven behavior over the production `validate_miniflux_account` path:

- plain HTTP Miniflux installations remain supported;
- custom HTTP headers reach the server on the real Rust request;
- public/system trust anchors complete the handshake and reach the HTTP layer;
- invalid and untrusted certificates are rejected as a transport failure and never validate as a Miniflux server;
- user-installed CA anchors are trusted, matching the legacy Flutter client; the same server is rejected before the anchor is installed and accepted afterwards.

Runtime acceptance on 28 September 2026 passed the full transport suite on an API 29 / Android 10 `arm64-v8a` emulator and on an API 37 `arm64-v8a` emulator with 16 KB pages. `android/Build/test-transport-runtime.sh` is the canonical entry point; it selects one explicit device, runs only the E1-C instrumentation tests and drives both user-CA phases. The public/system CA gate is a deliberate online integration test and is not part of the offline `android/Build/test.sh` gate.

### E1-D — Android Core runtime ownership

E1-D is complete. `FluxApplication` owns one process-scoped `AndroidCoreRuntime`, which owns zero or one active Core session including its `Flux` object and event subscription. It uses bounded local and remote execution lanes so synchronous Core work stays off-main and slow remote work cannot head-of-line-block local reads. Activity recreation does not create a Core session; process death recreates an empty runtime that later account state bootstraps. Close and replacement stop new work and wait for active calls before closing the subscription and Core. One-emulator acceptance covers owner recreation, off-main local/remote calls, lane isolation, clean close and replacement.

No feature-domain duplication is allowed in this layer.

### E1-E — Credential and preference storage proof

E1-E is complete. `FluxApplication` process-owns the separate credential and preference stores. Credentials use a versioned AES-256-GCM envelope with context AAD, atomically stored in app-private `noBackupFilesDir`; the AES key is an `AndroidKeyStore` key authorized only for GCM encrypt/decrypt and never requires per-use user authentication. API keys and custom headers never enter DataStore, and clearing credentials removes both envelope and key alias. This supports normal locked-screen/background access after first unlock, but declares no Direct-Boot secret storage.

Non-secret native preferences use one process-scoped Preferences DataStore (1.2.1) with typed asynchronous access. API-29 runtime acceptance proves encrypted relaunch access, tamper/corruption failure, no plaintext in the envelope, Keystore metadata, preference persistence and background access without an Activity.

### E1-F — Production-upgrade migration feasibility

E1-F is implemented. Its physical production-upgrade acceptance was deliberately deferred at this E1 checkpoint and was later completed through the E9 real-device production-upgrade pass. The isolated production-identity Migration Probe has a read-only native reader for the exact Flutter secure-storage format and for legacy database, playback, media, widget, and auto-backup discovery. It writes only a redacted cache report, compares legacy-source fingerprints and relevant Keystore aliases before/after, and has a signer/version-guarded in-place upgrade script. It performs no migration or new-Core/store write.

On a production-identity test build installed over the current Flutter app, prove read-only access to:

- legacy account URL/API key;
- custom headers and selected compatible settings;
- news_database.db;
- SharedPreferences playback progress;
- legacy downloaded media and metadata;
- widget SharedPreferences/configuration evidence;
- any legacy auto-backup artifact that is intentionally retained.

The test build must not delete or convert those sources in place.

### E1-G — Durable native paths and backup exclusions

E1-G is complete. `AndroidStoragePaths` is the canonical native path layout: Core data,
media, logs and widget projection use separate `noBackupFilesDir/flux-native/` children;
regenerable Core cache uses `cacheDir/flux-native/core-cache`. This is disjoint from
`news_database.db`, `audio_cache`, legacy SharedPreferences/DataStore and legacy backup
artifacts. Android automatic cloud backup and device transfer explicitly exclude every
database, file, shared-preference, external and root sandbox domain; `noBackupFilesDir`
also excludes the native roots by platform contract. Configuration backup/restore remains
the only intended portable configuration handoff.

E1-A through E1-G are complete. E1-H is next. At this historical checkpoint the
E1-F physical production-upgrade acceptance was deferred to E9; it has since
been completed by the E9 real-device production-upgrade pass.

### E1-H — CI and test gate

E1-H COMPLETE. The canonical local gate is `android/Build/test.sh`; GitHub Actions runs
it together with `android/Build/build-app.sh productionRelease` and shell syntax validation
on Linux. The baseline pins JDK 17, Android SDK platform 36, Build Tools 36.0.0, NDK
27.0.12077973, Rust 1.98.0 and the `aarch64-linux-android`/`x86_64-linux-android` targets.
It does not start an emulator or run targeted E1-B through E1-F platform acceptance suites.
Those remain targeted proofs. The physical E1-F production-upgrade requirement was
subsequently satisfied by the E9 real-device upgrade pass.

Phase E1 COMPLETE. All nine E1 exit conditions are met: the production-identity emulator
proof satisfies the read-only migration-spike condition, while the production-upgrade physical-device repetition was subsequently
completed in E9. E2 NEXT.

### E1 exit conditions

E2 may begin only when:

1. native Android Debug builds through the repository;
2. Kotlin successfully calls the current UniFFI Core;
3. Core calls are off-main and one process-scoped Core owner is proven;
4. TLS/platform trust is characterized and acceptable or a narrow corrective plan is committed;
5. development and production identities are explicitly separated;
6. a production-identity upgrade spike can read the required legacy Android sources without mutating them;
7. Core/new-native paths are isolated from legacy paths;
8. production signing/update prerequisites are known;
9. no unresolved E1 issue requires replacing UniFFI or the shared Core architecture.

## 13. E2 — Adaptive App Shell, Account and Settings Foundation

E2 implements the native Android shell and normal Settings hierarchy.

Required scope:

- adaptive phone/tablet/foldable navigation;
- account creation/replacement/removal;
- Miniflux validation and custom headers;
- server-version presentation;
- HTTP warning;
- Rebuild Local State and Remove Account semantics;
- native appearance/accessibility behavior;
- Navigation Settings and Startup Scope;
- Article presentation/settings;
- feed preference UI;
- Background Sync preference surface;
- Config Backup/Restore entry points and startup restore path;
- Open Source/About/version/legal;
- Support Diagnostics shell where settings dependencies are needed.

Use Material/Android conventions. The accepted Article List chrome intentionally shares Flux's capsule concept with iOS while remaining a native Compose/Material implementation. Compact phone portrait keeps the scope capsule at the top and the action capsule floating above the bottom system inset; compact landscape moves the action capsule to the top-right. Wide tablet/foldable windows use persistent 320 dp navigation with the duplicate scope capsule hidden and up to five direct actions at the top-right. That persistent navigation can be collapsed without leaving the wide layout; the collapsed state restores an interactive scope capsule at the top-leading position, keeps actions at the top-right, and opens the navigation transiently so it can be expanded again.

Config Backup remains platform-specific. Android uses BackupPlatform.Android and an Android platform-settings payload. A backup is not promised to be portable to or from iOS unless a future explicit cross-platform backup contract is created.

### E2-F — Configuration Backup / Restore

Status: **COMPLETE**

Android configuration backup and restore is complete and test-gated.

Implemented:

- uses the existing encrypted Core `.fluxbackup` format
- Android Storage Access Framework is used for backup export and restore import
- no backup files are stored in app-private runtime storage
- Android platform settings are carried in the versioned `AndroidBackupSettingsV1` payload
- Android backup payload includes:
  - navigation preferences
  - startup scope
  - article presentation/settings
  - swipe actions
  - action-bar ordering
  - custom headers
- Core-owned settings remain exclusively in the Core backup payload
- media/feed settings owned by Core are not duplicated in the Android platform payload
- credentials remain in the Android Keystore-backed credential store
- no plaintext credential preference storage was introduced
- no Android-specific backup cryptography was introduced
- restore validates the backup before mutation
- existing-account restore replaces Core configuration, credentials, Android platform settings and runtime state transactionally
- fresh-install restore supports restoring before a normal account bootstrap has completed
- failed existing-account restores restore the previous:
  - Core configuration snapshot
  - credentials
  - Android platform settings
  - runtime session
- failed fresh-install restores:
  - reset the temporary persisted Core state
  - restore the previous Android preference state
  - close the temporary runtime session
  - clear restored credentials
- rollback failures publish a recoverable bootstrap state rather than exposing an inconsistent account as ready
- restore runs inside the existing configuration/account lifecycle lock
- successful restore publishes the restored account only after Core, credentials, platform settings and runtime replacement have completed

Test coverage includes:

- Android backup payload round-trip
- schema-version validation
- stored-enum validation
- startup-target normalization
- swipe-action consistency validation
- action-bar ordering validation
- existing-account successful restore
- fresh-install successful restore
- rollback after Core mutation
- rollback after credential mutation
- rollback after platform-settings mutation
- partial platform-preference mutation rollback
- rollback after runtime replacement failure
- fresh-install Core reset
- fresh-install preference restoration
- runtime cleanup
- credential cleanup
- rollback-failure / recoverable-error publication
- failure before mutation leaves existing state unchanged
- transaction mutations execute inside the configuration lock

The previously outstanding injectable-controller / transaction rollback test gate is complete.

No Core or UniFFI contract changes were required for the Android restore transaction work.

`AndroidStoragePaths` was reviewed only as required for E2-F to ensure SAF configuration backups are not stored there. The broader `AndroidStoragePaths` ownership/lifecycle review remains intentionally deferred to its later Phase-E work and is not an E2 completion blocker.

### E2-G — About, Legal and Support Diagnostics

Status: **COMPLETE**

The native Android settings shell now includes the E2-G support and informational surfaces.

Implemented:

- About screen
- application version information
- Open Source information
- legal information
- Support Diagnostics settings destination
- persistent bounded support log
- optional persisted debug logging
- structured diagnostic records
- native Android diagnostics and shared-Core diagnostics use the same Android support-diagnostics model
- Core sessions are initialized with the Android diagnostic listener
- diagnostic log viewer
- log search
- log-level filtering
- newest-first presentation
- per-entry copy support
- clear-logs flow with confirmation
- diagnostics export through the Android sharing flow
- diagnostics export is exposed through a scoped `FileProvider`
- known credential values are redacted from diagnostic output
- common authorization/API-key patterns are redacted
- diagnostic retention is bounded to avoid unbounded app-private storage growth

The support-diagnostics implementation has focused JVM coverage and is included in the canonical Android test gate.

No Core/UniFFI contract change was required for E2-G.

### E2 completion

Status: **COMPLETE**

Phase E2 — Adaptive App Shell, Account and Settings Foundation — is complete.

The completed E2 scope includes:

- adaptive native Android app shell and navigation, including compact transient navigation, persistent wide navigation, and a collapsible wide-navigation state
- account bootstrap and account management
- custom headers and account/server handling
- navigation preferences
- article settings
- swipe-action settings
- action-bar configuration
- feed preferences
- background-sync settings and scheduling integration
- downloaded-data settings
- configuration backup and restore
- fresh-install configuration restore
- transactional restore and rollback coverage
- About / Open Source / Legal surfaces
- Support Diagnostics

Validation:

- `./android/Build/test.sh` — PASS
- Android CI gate — PASS
- production Android build gate is part of the canonical CI workflow
- shell-script syntax validation is part of the canonical CI workflow

The larger `AndroidStoragePaths` ownership/lifecycle review remains deferred to the later Phase-E slice where it is already planned. It does not block E2 completion.

**Phase E2 is COMPLETE.**

**Phase E3 is COMPLETE. E4 — Actions, Search, Sync and Mutations — is NEXT.**

## 14. E3 — Native Article Timeline / Article Presentation

E3 implements the native Android Article List over Core query/page APIs.

### E3-A — Timeline paging foundation

Status: **COMPLETE**

Implemented on 1 October 2026:

- the E2 Timeline placeholder is replaced by a Compose `LazyColumn` backed by Core `article_page`;
- Article IDs are the stable lazy-list keys;
- local Timeline queries use bounded 64-row Core keyset pages and retain the authoritative first-page total;
- All News / Starred / Category / Feed map directly to the existing Core scope/starred filters;
- transient Unread/All and sort values are represented only as Timeline presentation selection, not persisted Settings;
- first-page replacement and later-page append are generation-owned and discard stale completions;
- the Android Core runtime publishes a monotonic read-only session generation so account/session replacement invalidates old Timeline requests;
- duplicate rows are rejected by stable Article ID and duplicate-only/repeated-cursor pages terminate pagination rather than looping;
- loading, empty, initial-error and append-error states are native Compose presentation states;
- synchronous Core paging remains on the existing bounded local Core execution lane, never the main thread;
- focused JVM tests cover scope/query mapping, first-page total ownership, append/deduplication, query replacement, Core-session replacement and pagination termination.

Validation:

- Android pull-request CI gate — PASS
- canonical gate included unit tests, lint, development assembly and production release build
- no Core/UniFFI API change was required

### E3-B — Productive article presentation and native image pipeline

Status: **COMPLETE**

Implemented on 2 October 2026:

- productive Compact, Visual and Visual Compact Compose row presentations;
- shared feed/source metadata, headline, publication-time, Core reading-time and preview semantics;
- shared accessory ordering for unread, star, comments and audio;
- page-level batched Core audio projection without per-row Core calls;
- one app-wide Coil 3.6.3 image loader with bounded memory and disk caches;
- Compact performs no article-image work, while visual modes request images at presentation constraints;
- the Timeline's Core total is used for the Settings-controlled article-count presentation;
- the Android build/toolchain baseline was modernized to current stable components where available: AGP 9.4.0, Gradle 9.7.1, Kotlin/Compose compiler 2.4.20, current stable AndroidX/Material/Coil libraries, NDK r29, and compile SDK 37 with stable runtime target SDK 36;
- CI uses the current Android CLI to provision API 37 tooling while keeping production runtime targeting on stable Android 16/API 36;
- focused tests cover presentation policy, image-mode behavior, accessory ordering, RFC3339 publication parsing and batched audio projection.

Validation:

- Android pull-request CI gate #20 — PASS
- canonical gate included unit tests, lint, development assembly and production release build
- SDK/NDK provisioning, Rust/UniFFI, Kotlin compilation, Compose lint and production release build all passed on the modernized toolchain

### E3-C — Targeted article status projection

Status: **COMPLETE**

Implemented on 2 October 2026:

- Android Core events are tagged with the owning Core-session generation before entering the app event stream;
- stale events from retired account/Core sessions are ignored by the Timeline;
- structural Timeline data (ordered ArticleSummary rows, IDs and paging) is separated from per-row presentation state (isRead, isStarred, revision);
- status-only read/unread and star/unstar changes update only the affected row presentation state and keep the structural articles snapshot/list instance stable;
- filter exits still remove affected loaded rows structurally without a full page reload;
- filter re-entry for an article that is not currently loaded triggers a bounded first-page snapshot refresh because no complete ArticleSummary exists locally for that unseen article;
- filtered selection totals are refreshed through Core count queries so non-loaded status changes cannot leave the title count stale;
- sync-complete events with changed article data replace the bounded Timeline snapshot;
- the existing paging, image-loading and batched media-projection architecture remains unchanged;
- focused JVM tests cover visible status patching, stale-session rejection, unread-filter removal/re-entry, starred-scope removal/re-entry, and non-loaded count updates.

Validation:

- Android pull-request CI gate #25 — PASS
- canonical gate included unit tests, lint, development assembly and production release build
- no Core/UniFFI API change was required

### E3-D — Native Android Scrollover

Status: **COMPLETE**

Implemented on 2 October 2026:

- Compose-native Scrollover detection uses only LazyList scroll progress plus the first-visible item index; no per-frame row geometry or visibility qualification is required;
- each scroll interaction records the first-visible index at interaction start and the highest first-visible index reached before the list becomes idle;
- reverse movement never erases forward progress; candidates are emitted once, at interaction end, for the stable Article IDs in [startIndex, highestReachedIndex);
- known programmatic scrolls explicitly suppress Scrollover tracking and synchronize the idle baseline afterwards;
- Scrollover read mutations use the existing Core bulk read API and are bound to the active Core-session generation;
- optimistic read presentation remains non-structural: only the affected per-ID presentation state changes, while the ordered structural Timeline snapshot remains untouched;
- pending Scrollover mutations remain process-scoped and generation-bound so Activity recreation cannot lose accepted work;
- failed Core writes roll back only the affected presentation state and re-arm the affected IDs;
- the Timeline count is updated once at interaction completion instead of once per crossed article, avoiding global scroll-adjacent recomposition pulses;
- navigation refreshes are conflated across Core-event bursts to avoid per-event scroll-adjacent reload work;
- focused JVM tests cover first-item handling, forward/backward movement, highest-index accumulation, programmatic-scroll exclusion, append-only paging, snapshot replacement, bulk mutation behavior and rollback.

E3-E physical-device acceptance subsequently found and closed the remaining Scrollover presentation-feedback gap without changing the E3-D architecture:

- successful Scrollover reads publish one native confirmation haptic per completed user scroll interaction, never one vibration per article/Core event;
- a qualified successful Scrollover burst exposes a native Undo snackbar; qualification requires three successful reads within the short burst window, later successes extend the active group, inactivity closes it after 4 seconds and the group has a 15-second maximum lifetime;
- Undo writes the exact qualified Article IDs back to unread through the generation-bound Core bulk mutation path, re-arms those IDs for future Scrollover qualification and emits a lighter native selection haptic only after success;
- stale/account-replaced Undo state is rejected and failed Undo does not publish success feedback;
- focused JVM tests cover haptic batching, Undo qualification, expiry, successful unread restoration and session replacement.

Validation:

- Android pull-request CI gate #27 — PASS
- unit tests, lint, development assembly and production release assembly all passed
- no Core/UniFFI API change was required

### E3-E — Physical-device, performance and UI acceptance

Status: **COMPLETE**

E3-E was accepted on 2 October 2026 after physical-device use of the Native Dev Google Play internal-test build.

Accepted results:

- normal reading-speed and fast scrolling with realistic article sets and real images are smooth on the tested physical Android device;
- Scrollover remains smooth with Mark Read on Scrollover enabled, including real touch/fling interaction and batched read mutations;
- Compact, Visual and Visual Compact presentation, native image loading, adaptive layout, Light/Dark presentation and navigation chrome were refined during physical-device use;
- no measured evidence currently justifies replacing the Compose `LazyColumn` renderer or introducing a second rendering architecture;
- small UI and performance findings discovered later may be fixed as normal refinement without reopening E3 unless they expose a concrete architectural contradiction.

Acceptance corrections implemented during E3-E include:

- the process-scoped app owner retains the Android Timeline presentation store across Activity recreation, so orientation and Light/Dark configuration changes keep the current local snapshot instead of constructing an empty Timeline store;
- the selected scope is restored only when the retained Timeline belongs to the active Core-session generation; a real account/session replacement still re-evaluates Startup Scope;
- Timeline reset/scroll-to-top occurs only for a semantic context/session change; a pure configuration recreation no longer counts as a context change;
- ordinary Activity recreation no longer requests `SyncReason.APP_START`; the internal AppStart reason remains limited to account activation/replacement bootstrap where an initial synchronization is required;
- decorative feed icons avoid duplicate TalkBack speech and unread state carries explicit accessibility semantics;
- native read/star/Scrollover feedback uses system haptics rather than direct vibration control;
- Scrollover Undo is generation-safe and uses the shared Core bulk mutation path;
- Timeline composition work was reduced by hoisting row-width decisions, adding lazy-list content types, batching feed-icon loading, removing per-row BoxWithConstraints, avoiding Timeline-wide recomposition on scroll start, and separating volatile row presentation from the structural list snapshot;
- read/unread presentation is geometry-stable like iOS: the headline keeps one fixed font weight, feed/publication/preview/accessory state changes are colour/opacity-only, and star/unread use permanently reserved slots so marking a row read cannot change its measured height or text wrapping.

This E3 checkpoint originally deferred the physical UniFFI/production-upgrade proof to E9. The production Flutter-to-native upgrade path was subsequently accepted on physical hardware during E9; the current E9 section records the remaining focused Playback Verification v2 recheck.

**Phase E3 is COMPLETE.**
### Baseline renderer

Start with Compose LazyColumn or the current idiomatic Compose lazy-list equivalent.

Use:

- stable Article IDs;
- bounded Core pages/read models;
- image loading sized for presentation;
- one native image pipeline/cache;
- no synchronous Core/network/image decode on the main thread;
- batched article-level media projection where already provided by Core;
- status-only presentation updates must not replace the structural Timeline snapshot; each loaded Article ID owns an independently observable row-presentation state so unrelated visible rows are not invalidated;
- read/unread visual treatment must be geometry-stable: do not change title font weight, slot allocation, line limits or any other measurement-affecting property as a consequence of read state.

Do not introduce RecyclerView as a precautionary workaround.

### Required presentations

Support the shared mobile modes:

- Compact;
- Visual;
- Visual Compact.

Preserve shared semantic ordering and the date/reading-time/accessory contracts in MOBILE_PRODUCT_SEMANTICS.md while using Android-native typography, spacing and surfaces.

### Scrollover

Implement the shared Scrollover behavioral contract with Android/Compose-native scroll state. Do not port the UIKit geometry tracker line-for-line: Android intentionally commits one ID batch when scrolling becomes idle, using the interaction start index and highest reached first-visible index.

Known programmatic movement must be explicitly suppressed. Snapshot replacement clears in-flight Scrollover progress; append-only paging preserves it.

### Performance acceptance

Performance is measured on physical Android devices, with the first meaningful real-device product pass occurring in E3 once the shell, account flow and Timeline make the native app realistically testable. The API-29 runtime floor remains covered by the E1-B emulator smoke; E3 physical-device performance acceptance uses representative supported hardware and a contemporary device where available. Test with realistic large article sets and real article images.

Performance acceptance must use a release-equivalent build. The Google Play internal-test artifact is `developmentRelease`; it shares the same `release` build type, R8 optimization, resource shrinking, Rust release build and Baseline Profile input as `productionRelease`. Debug builds remain diagnostic/development tools and are not authoritative evidence for product performance.

The app owns a Baseline Profile producer module. Baseline Profile generation uses a deterministic fixture Timeline routed through MainActivity only when the plugin-generated `nonMinifiedRelease` build type is running and a private profile-capture Intent extra is present. Normal Debug, `developmentRelease` and `productionRelease` launches cannot activate that path; optimized Release builds can remove the unreachable branch. The fixture uses deterministic ArticleSummary values and an existing local app image resource, so Timeline profiling is reproducible without Miniflux credentials, network access or mutable user data while exercising the productive Timeline row, swipe-container, image, metadata and publication presentation code. Generate/update the profile on one connected API-33+ device with `bash android/Build/generate-baseline-profile.sh`, then commit the generated `app/src/main/generated/baselineProfiles` output before using the next Play internal-test build for performance acceptance.

The physical Timeline acceptance pass completed before this release-performance pipeline was finalized. It remains valid as a functional/device acceptance result, but future claims about marginal jank or renderer-level performance must be reconfirmed on the optimized Play `developmentRelease` path before introducing new renderer/cache/recomposition complexity.

Use Android Macrobenchmark/JankStats/tracing to identify actual bottlenecks if reproducible performance regressions remain after R8 and the committed Baseline Profile are active. Only replace or specialize the renderer when measured release-build evidence shows the default Compose path cannot meet the product requirement.

E3 is accepted after normal reading-speed scrolling, fast scrolling, image loading, mutations and Scrollover were verified without systematic jank on physical hardware.

## 15. E4 — Actions, Search, Sync and Mutations

### E4-A — Semantic Article List actions and transient list controls

Status: **COMPLETE**

Implemented on 3 October 2026:

- the app shell now owns the complete transient `AndroidArticleTimelineSelection` instead of reconstructing default Unread/Oldest values from the selected scope;
- scope changes preserve the current transient All/Unread and sort choices while remaining non-persistent presentation state;
- All/Unread and Oldest/Newest controls are exposed through native Material 3 menu presentation and continue to use the existing E3 semantic-reset path, including return to the natural list start;
- Activity/configuration recreation retains the complete selection only when the retained Timeline belongs to the active Core-session generation;
- a pure `AndroidArticleListActionPolicy` resolves persisted semantic action priorities into direct and overflow actions without storing Compose control identities;
- contextual availability follows the shared mobile contract: Mark All as Read is unavailable for Starred, and Mark All as Read & Next exists only for Category/Feed when a next sibling is available;
- unavailable actions are filtered only at presentation-resolution time and never rewrite the persisted semantic configuration;
- focused JVM tests cover transient selection transitions, action availability, direct-slot priority, overflow completeness and contextual filtering;
- the E3 Timeline store, renderer, paging architecture and Core/UniFFI surface remain unchanged.

### E4-B — Productive article actions, mutations and swipe interaction

Status: **COMPLETE**

Implemented on 3 October 2026:

- configured leading/trailing semantic swipe actions are now resolved per article and rendered by a Compose-native horizontal gesture adapter;
- partial swipe only reveals actions, tapping a revealed action executes it, and a full swipe executes only the configured outer/full slot;
- a missing contextual outer action is omitted without promoting the configured inner action to Full Swipe, and reversing an already-open swipe must return to neutral before the opposite side can open;
- long-press article actions plus a TalkBack custom action expose Read/Unread, Star/Unstar, Original, Miniflux, Comments, Copy Link, Share and third-party Save when applicable;
- media swipe semantics remain persisted but are contextually omitted until E6 provides the native media runtime;
- explicit Read/Unread and Star/Unstar use optimistic row state, generation-bound Core writes, serialized mutation delivery, per-article stale-completion tokens and rollback on failure;
- successful explicit Read respects the existing Remove Articles When Read preference, while successful unstar removes a row only from the Starred scope;
- explicit Original open marks the article read without stacking read haptic feedback; Comments does not mark the article read;
- Original, Comments, Share and clipboard handling use Android platform APIs, while Miniflux URL resolution and third-party Save remain Core-backed;
- a generation-bound remote execution helper prevents a retired account session from servicing third-party Save work;
- focused JVM tests cover swipe-slot preservation, contextual action availability, URL validation, optimistic mutation/rollback, successful structural removal and retired-session completion suppression;
- no Core/UniFFI API or E3 paging/renderer ownership change was required.

The normal article-row Open action remains intentionally deferred until E4-D, because the existing Reader preference must not be temporarily bypassed by forcing every row tap to the original URL. E4-D adds Reader and then activates normal row Open with the complete routing contract.

### E4-C — Manual Sync, pull-to-refresh and scope-wide read workflows

Status: **COMPLETE**

Implemented on 3 October 2026:

- the fixed Article List Sync control now drives the existing process-scoped `AndroidSyncCoordinator` with `SyncReason.MANUAL`; Compose does not own a second Sync state machine;
- a running Manual Sync exposes cooperative Cancel through the existing Core `SyncCancellation` handle, while startup-owned Sync runs are not user-cancellable through the Manual Sync control;
- the Timeline uses Material 3 `PullToRefreshBox` and routes pull-to-refresh through that same Manual Sync path; an existing foreground Sync suppresses duplicate refresh requests;
- Sync failure keeps the local Timeline visible and surfaces the coordinator's sanitized recoverable message; cancellation is treated as a normal terminal outcome rather than a network failure;
- the persisted semantic Article List configuration is now productive in the Android top bar: fixed Sync, configured direct slots and the always-reachable More overflow share the E4-A availability policy;
- Filter/Sort, Search, Listening List and Settings actions route through their existing native destinations/presentation paths, while Mark All actions use an explicit destructive confirmation;
- Mark All as Read queries the Core for the exact unread IDs in the current All/Category/Feed scope using `Unread + StarredFilter.All + NewestFirst + limit=0`, then passes exactly those IDs to `setReadStateBulk`;
- Mark All as Read & Next computes its target from the current visible navigation order before mutation, performs no wrap-around, and navigates only after the bulk mutation succeeds;
- visible-feed order respects Hide Empty navigation semantics, including category grouping and orphan-feed placement; Category & Next likewise skips categories hidden by the current visible navigation projection;
- successful plain Mark All reloads the current Timeline at its natural start; Mark All & Next avoids reloading the old scope and lets the successful scope transition perform the next Timeline reset; both emit one confirmation while per-article Core events are suppressed from producing an N-event haptic/reload burst;
- stale selection/session completions cannot trigger a bulk write, a Timeline replacement or an `& Next` navigation;
- focused JVM tests cover Manual-only cancellation, next-scope ordering/no-wrap behavior, the exact Mark-All query, exact bulk IDs, failure behavior and stale-selection suppression;
- no Core/UniFFI API change was required.

### E4-D — Reader overlay, normal article routing and remote Search

Status: **COMPLETE**

Implemented on 3 October 2026:

- Reader is temporary presentation rather than a Navigation Compose destination: the active Timeline or Search surface remains mounted underneath and retains its list state;
- compact portrait uses a near-full-height closable Reader surface over the list, while wider/landscape/tablet layouts use a centered floating panel; Android Back, the close control and the outside scrim dismiss only Reader;
- Reader content is loaded from the semantic Core `ReaderDocument`, including headings, paragraphs, inline emphasis/code/links, images, lists, quotes, code blocks, rules, external content and the simplified/truncated notice;
- Reader requests are process/session-generation bound; switching article, dismissing Reader or replacing the account invalidates stale completions;
- normal Timeline row taps are now productive and always mark the article read before routing;
- the existing global Open Article preference selects Reader versus web opening, and web opening additionally honors the feed-specific `openInMiniflux` preference; explicit Original, explicit Reader and explicit Miniflux remain independent actions;
- Android web routing first attempts a non-browser App Link/deep-link handler; when no dedicated app can handle the URL, Flux keeps the user in the app flow with an AndroidX Custom Tab instead of handing the URL straight to the external default browser; Android 10 uses handler-set comparison for the same compatibility behavior;
- Search remains a real secondary Navigation Compose destination, so Back returns to the preserved News Timeline rather than treating Search as a Reader-style overlay;
- Search uses Core/Miniflux `searchArticles` with its own 50-item offset pagination, request-generation stale suppression and result de-duplication; it does not create a local FTS/index;
- Search reuses the normal Android article row renderer, swipe configuration, context actions, feed icons and available audio projection;
- Article publication rows mirror the accepted iOS temporal semantics: relative publication time carries a small history/clock icon, optional Miniflux reading time is an inline Material Article icon plus duration after the centered dot, and audio articles substitute the reading-time document icon with headphones;
- Search chrome uses a single stable Material text-field surface with an integrated leading Search action, in-field progress/clear affordance, IME Search handling and focused tonal treatment; initial/no-result states use a centered icon, headline and supporting text rather than a bare sentence;
- Search loading feedback is intentionally singular: the in-field progress indicator is the only initial-search spinner; the result area does not render a second centered progress indicator;
- Search Read/Unread and Star/Unstar use the Core search mutation APIs with optimistic presentation and rollback on failure;
- opening a Search result follows the same normal Reader/original/Miniflux routing policy; Search Reader uses `readerDocumentForSearch` and closes back to the current Search result list;
- Comments still do not mark read, while Original, Reader and Miniflux article-opening actions do;
- Search/Reader state is app-process scoped but invalidated on Core-session replacement, so Activity recreation does not manufacture a second domain owner or stale account presentation;
- no Core/UniFFI API change was required.
- Article List chrome uses a shared Material capsule treatment: compact portrait keeps the action capsule floating above the bottom system inset, compact landscape moves it to the top-right, persistent tablet navigation hides duplicate scope chrome and keeps up to five direct actions at the top-right, and a collapsed persistent-navigation state restores the interactive scope capsule at top-leading while retaining top-right actions;
- only compact portrait reserves Timeline and Snackbar clearance for the floating bottom action capsule; persistent and collapsed-persistent tablet states do not reserve bottom-action space;
- swipe presentation keeps the E4-B 0-2-action/full-swipe contract but follows Material dismissal visuals with a continuous tonal reveal, circular icon targets, an action-colored armed full-swipe state and one selection haptic when crossing the threshold.
- a successful explicit Read → Unread transition re-arms that Article ID in the Scrollover tracker; failed unread writes do not re-arm, and external Core unread events also re-arm the article.
- the article long-press menu uses Material leading icons and visual grouping for state, opening and share/save actions instead of an undifferentiated text-only list.
- full-swipe dispatch uses the latest recomposed action callback so repeating Read/Unread or Star/Unstar full swipes toggles against the current article state instead of a stale pre-mutation snapshot;
- Starred is an all-read-state scope: Core queries force `ReadFilter.ALL` and read-filter controls are omitted while Starred is active, while the user's underlying All/Unread selection is preserved for returning to normal scopes.
- swipe visuals use flat Material action zones rather than circular/capsule targets: partial reveal keeps up to two full-height tonal zones with bare icons, while the configured outer action expands into the continuous background for full swipe and becomes the sole visible action after the threshold;
- swipe backgrounds use the final measured Article Row height so tonal action surfaces span the complete item and icons remain vertically centered; action zones are 80 dp with 28 dp icons (30 dp while full-swipe armed), and Article Rows do not insert separator dividers.
- the floating Article List action capsule keeps the same semantic controls but uses tighter chrome and smaller visual icons; active Sync is represented by a thin progress ring around the current Sync/Cancel glyph instead of replacing the button with a standalone spinner.
- Sync idle presentation uses a single clockwise Material refresh glyph; while any foreground Sync is active the title-capsule count slot shows `Syncing…`, and a successful Manual Sync temporarily replaces the Sync glyph with a checkmark for 1.5 seconds. Cancelled, failed and startup Sync runs do not show the success check.

E4-D and the complete E4 feature surface are accepted. The canonical Android CI gate is green and the physical-device acceptance pass covered the productive Timeline/Scrollover behavior, Manual Sync, Search/Reader presentation and normal article interaction. The accepted E4 implementation was merged to `main` in PR #23 on 4 October 2026 (merge commit `ab72c9cc`). New UI or performance findings discovered after this point are normal follow-up work and do not reopen E4 unless they expose a concrete architectural or product-contract contradiction.

E4 completes interactive Newsreader behavior:

- semantic swipe actions;
- context/overflow article actions as appropriate on Android;
- configurable semantic Article List actions;
- All/Unread and sort controls;
- Search using the normal article presentation renderer with Search-specific pagination;
- pull/manual refresh;
- cooperative Manual Sync cancellation;
- read/unread;
- star/unstar;
- third-party save where configured;
- Mark All as Read;
- Mark All as Read & Next;
- Reader/browser/share/comments/Miniflux routing;
- optimistic mutation feedback and stale-generation suppression;
- lifecycle-safe sync coordination.

The Android action configuration stores semantic action IDs/priorities, never Compose control identities.


### E4 acceptance addendum — release performance and final hardening

The final E4 acceptance state includes the release-performance and correctness hardening completed immediately before the E4 merge:

- release-equivalent Android builds use R8 minification, resource shrinking, Rust release artifacts and the committed Baseline Profile; the Google Play internal-test `developmentRelease` remains the authoritative path for marginal scrolling/jank assessment on physical hardware;
- generated Baseline Profile source files under `android/app/src/main/generated/baselineProfiles/` are committed inputs, while producer-module Gradle output such as `android/baselineprofile/build/` is ignored and must never be committed;
- Baseline Profile capture uses the deterministic Timeline fixture described in the E3 performance contract. It is reachable only in the plugin-generated `nonMinifiedRelease` capture variant with the private profile Intent extra; normal Debug, `developmentRelease` and `productionRelease` launches cannot activate it;
- Core runtime events are correctness-sensitive and use lossless process-scoped delivery rather than a finite `DROP_OLDEST` SharedFlow buffer. Local and remote Core worker lanes remain deliberately bounded;
- structural Timeline state changes no longer perform article-index or row-presentation side effects inside retriable `StateFlow.update` transforms; list state is committed first and the associated single-writer bookkeeping is then reconciled;
- Compose-derived Article ID/feed-ID projections depend on the actual Article list rather than only list size/query generation, so equal-size replacements cannot retain stale projections;
- persisted Article presentation preferences must be loaded before the Timeline renders preference-dependent rows; a transient default preference frame is not part of the accepted UI;
- Mark as Read on Scrollover is optimized for normal reading-speed scrolling: one gesture commits the crossed Article IDs when scrolling ends, the end-of-list path consumes all remaining crossed items, and changing an Article's read state must not alter row/list geometry or cause Timeline jumps;
- the floating Article List action capsule scales with Android system font scale from the accepted 1.0 baseline up to a bounded 1.35 factor. Button/icon/progress dimensions and compact-portrait Timeline/Snackbar clearance scale together so accessibility sizing cannot make the capsule overlap content;
- compact-phone Reader presentation intentionally has no clipped drop shadow. In dark mode the Reader uses a distinct Material container surface above the True Black Timeline; its scrim is edge-to-edge behind status/navigation bars while the Reader surface itself respects safe drawing insets.

The final hardening deliberately does **not** introduce speculative reset/event batching, renderer replacement, additional image/cache layers or broad recomposition optimizations. Those ideas are not E4 debt. Revisit them only if an optimized Play `developmentRelease` on physical hardware reproduces a concrete performance problem; use Macrobenchmark/JankStats/tracing before changing the accepted renderer architecture.

Contextually invalid actions are omitted rather than represented as durable disabled state.

## 16. E5 — Background Sync, System Notifications and Widgets

Status: **COMPLETE — implementation baseline accepted; follow-up defects handled as normal bug fixes**

E5 is accepted as complete for Phase-E sequencing. The native Android implementation now includes WorkManager background synchronization, Core-owned Resume freshness fallback, per-feed System Notifications with post-handoff acknowledgement, credential-free native widget projection/configuration, article routing from widgets, and persistent support diagnostics for background-sync / notification / widget handoff analysis.

This closure is an implementation milestone, not a claim that no real-device defects remain. Findings discovered after this point are handled as ordinary bug fixes and do not reopen E5 unless they expose a concrete architecture or product-contract contradiction. The current merge handoff intentionally allows follow-up repair of the latest Android CI regression introduced by the final diagnostics pass.


### Background Sync

Use WorkManager or the current platform-supported equivalent for deferrable periodic synchronization.

The user setting is only on/off. Android scheduling cadence is an implementation policy, not a user-facing interval. WorkManager timing is inexact and may be deferred by the OS.

Background work:

- reuses the app/Core sync contract;
- uses unique work to avoid duplicate schedules;
- does not create a second domain sync state machine;
- uses Core Delta/background semantics and freshness rules;
- uses SyncCancellation when the Worker is stopped after Core execution begins;
- reports completion/failure according to retry policy without publishing stale UI state.

Foreground/resume freshness fallback follows MOBILE_PRODUCT_SEMANTICS.md.

### System Notifications

Use Android's native notification APIs and runtime permission model.

Preserve the shared contract:

- off by default;
- configured per feed;
- at most one aggregated notification per enabled feed/candidate batch;
- Core candidate is acknowledged only after successful OS handoff;
- notification delivery acknowledgement is independent of in-app snapshot adoption.

Notification channels are Android presentation policy and must not become Core domain.

### Home-screen widgets

Prefer the current native Android widget stack when it meets the required layouts/configuration. The Android implementation may use Glance/RemoteViews mechanics; it must preserve the common data boundary.

Each widget instance owns its own platform configuration:

- scope: All News / Category / Feed / Bookmarks;
- read filter: Unread / All;
- sort: Newest First / Oldest First.

The widget process/component must not:

- initialize Core;
- open Core SQLite;
- access API credentials;
- call Miniflux;
- become a durable article-domain owner.

The main app writes a versioned credential-free widget projection plus bounded icon assets into Android app-private widget-readable storage. This is the Android equivalent of the shared widget projection principle; it is not an App Group/WidgetKit copy.

Android must not inherit the small fixed article-count limit used by WidgetKit snapshots. The Android projection may contain the complete locally retained article timeline and is paged from Core into Android-owned projection storage. "Bounded" on Android means bounded fields per article, bounded icon variants/assets, bounded projection generations and controlled storage ownership — not a fixed maximum number of article rows.

The Flutter Android widget is a UX reference rather than a fixed implementation contract. Preserve the useful product shape (responsive compact/status sizes and a large scrollable headline list), but evaluate native Android defaults first for background, corner radius, theming, padding and launcher integration instead of copying Flutter-specific styling.

The native large widget should use Android collection-widget mechanics appropriate for long timelines (for example RemoteViewsService/RemoteViewsFactory) rather than materializing the entire timeline into one RemoteViews payload. Per-widget configuration remains platform-owned.

Article taps route into the normal app article-open path. Widgets do not own a separate Open in Miniflux preference.

The legacy manual widget Sync button is intentionally retired in the native Android widget. Widget data refresh follows the normal app/background sync and local-mutation projection refresh paths; the widget must not expose a parallel Core sync path.

Current native implementation direction for E5-C/E5-D:

- Android persists a credential-free SQLite projection in `flux-native/widget` and publishes complete retained timelines into it using paged Core reads rather than a fixed article limit.
- Projection generations are atomically switched so a launcher never reads a partially written database; feed icons are stored once per feed/variant instead of once per article.
- Local read/star mutations refresh the projection through the existing single Core event consumer, avoiding a second competing Core event collector.
- The production provider identity remains `de.circle_dev.flux_news.FluxNewsWidgetProvider`.
- The large widget uses `RemoteViewsService`/`RemoteViewsFactory` collection semantics; compact sizes show scope/count/last-sync status.
- Each widget ID stores its own scope/read-filter/sort configuration.
- Article taps carry only the article ID into the app; the app resolves the current local Core article and uses the normal article-open flow.
- Initial styling deliberately uses native/system background and widget-radius behavior. Flutter-specific translucent backgrounds, bespoke colors and fixed corner radii are not part of the initial native contract and should be evaluated only after physical-device acceptance.

### Existing production widget component

The Flutter production app already has FluxNewsWidgetProvider and installed widget instances may survive an application update only if their Android component/configuration path remains valid.

E1/E5 must characterize the real production-upgrade behavior. Preserve the existing provider component identity where practical so users do not needlessly lose placed widgets. This compatibility requirement does not preserve the legacy widget data model.

## 17. E6 — Native Media, Listening List and Background Transfers

Status: **COMPLETE FOR SEQUENCING — device-tested; E7 unblocked**

The initial E6 foundation is implemented on branch `android-e6-media-runtime`:

- `FluxApplication` owns one process-scoped `AndroidMediaRuntime` over the existing `AndroidCoreRuntime`;
- a narrow Core-lifecycle participant boundary quiesces media before account replacement, local-state rebuild, account removal and configuration restore, then reattaches it only to the current Core-session generation;
- playback checkpoints are generation-bound Core writes and stale-session completions are ignored rather than adopted by a replacement account;
- Media3 1.11.1 provides the native ExoPlayer/MediaSession baseline;
- `AndroidMediaPlaybackService` is the single long-lived playback container, configured for spoken media, Android audio focus and becoming-noisy handling;
- the service is registered as a media-playback foreground service so later E6 background playback and E7 system/Android Auto integration build on the same player rather than introducing a temporary Activity-owned runtime;
- productive playback now resolves Core `PlaybackPreparation`, prefers a validated local media reference under the configured media root, falls back to HTTP(S), restores in-progress position and projects chapters/artwork source;
- Play/Pause/Stop, seek, ±30-second skip, 0.5x–3.0x playback rate, 20-second Core checkpoints, duration observation, natural completion/restart and the 30–180 minute sleep timer are implemented in the process-scoped playback coordinator;
- the playback coordinator controls the service through a Media3 `MediaController`, preserving the single-player service boundary needed by E7;
- the native Listening List destination is now backed by `listeningListFeeds()` + `listeningList(feedId:sort:)`, with feed filtering, sorting, progress presentation, multi-enclosure selection and direct control of the process-scoped Media3 playback coordinator;
- the Listening List includes a compact native playback surface over the same service-owned player, so playback state is not duplicated in Compose;
- article-level Listening List add/remove now uses the batched `articleAudioActionStates(articleIds:)` projection in Timeline and Search; no visible-row Core queries are introduced;
- Android background transfers are now Core-authoritative WorkManager jobs keyed only by enclosure ID: workers re-read current Core work after process death, apply Core network policy as WorkManager constraints, finalize deterministic files under the configured media root, and report only `downloadFinished`, `downloadFailed` or `downloadDeleted` back to Core;
- WorkManager is deliberately only the Android platform task registry, not a second domain state machine; Media3 `DownloadManager`/`DownloadIndex` is not used because the Core already owns durable download state;
- transfer reconciliation runs after startup, successful sync, media-policy changes, download/delete mutations and Core lifecycle replacement; stale native jobs are cancelled and deletions are deferred while an enclosure is actively playing;
- Listening List download/cancel/retry/delete controls are productive, including transient byte/total progress from the native worker runtime;
- Timeline and Search now retain the batched Core enclosure/download projection and expose article-level Download Audio as Download/Cancel/Retry/Delete semantics; multiple audio enclosures use one native chooser rather than per-row Core queries;
- worker completion/failure/deletion and every successful Core sync publish only an in-memory media revision signal so Timeline, Search and Listening List re-read authoritative Core state without introducing a second persisted transfer state;
- currently loaded playback remains live from Media3 at runtime cadence, while non-Now-Playing Listening List progress is refreshed from Core immediately after sync so remote Miniflux progress updates become visible without reopening the screen;
- the rich native Player surface is now implemented over the same service-owned Media3 player: local Core artwork bytes and remote HTTP(S) artwork, seek timeline, Play/Pause/Stop/±30 seconds, visible playback-rate and sleep-timer controls, completion Restart, active-chapter presentation/navigation and expandable Show Notes;
- Show Notes reuse `readerDocument(articleId:)` and the existing Android Reader renderer; the Player does not fetch or render article HTML through a parallel path;
- opening Player from a Listening List row prepares the selected enclosure without auto-starting playback, while the compact mini-player opens the same rich surface for the active item;
- media presentation now follows the accepted iOS D6 hierarchy while using Material 3 interaction patterns: artwork/header, seek, icon-based transport controls, compact rate/sleep status controls, chapter/show-notes cards and adaptive side-by-side layout on wide Android screens;
- Listening List rows mirror the same product hierarchy with tappable content, one compact Play/Pause icon control and overflow actions for audio/download/removal instead of exposing a strip of text buttons; top-level Back/filter/sort are native icon actions;
- the compact Now Playing surface is integrated into the portrait article-list bottom action dock, above the existing action icons, and disappears on Stop; the Listening List intentionally has no duplicate mini player;
- tapping a Listening List row opens a read-only player preview for that item without calling `preparePlayback()` or replacing the currently loaded enclosure; preview metadata, artwork, chapters, saved progress and Show Notes are read from Core, while only an explicit Play action switches playback;
- the currently loaded Listening List item is marked `Now Playing` while playing or paused so the relationship between the preview item and active playback stays visible;
- policy-driven media mutations now reconcile immediately: Listening List add/remove, Downloaded Data deletion, media-policy changes, playback completion/restart and retention evaluation all fan into one `reconcileAndSignal` path;
- changing download retention immediately runs `evaluateMediaCleanup()` before Android schedules resulting deletion work, while playback completion immediately surfaces Core-owned Delete-after-playback and Remove-completed-Listening-List effects;
- successful Core sync now reconciles an already loaded but idle Android player to the Core playback position, matching the proven iOS cross-device rule; actively playing audio is never force-seeked by sync;
- Listening List reload publication is request-generation guarded so stale filter/sort/media refresh work cannot overwrite a newer snapshot;
- media artwork no longer uses a second Android HTTP image stack: remote artwork goes through the app Coil pipeline, while embedded Core artwork is loaded lazily and held only in a bounded process cache instead of eagerly storing all artwork bytes in Listening List state;
- media transfer workers use fast IPv6/IPv4 fallback, bounded network timeouts, cooperative body-copy cancellation and explicit OkHttp-call cancellation when WorkManager stops the worker;
- foreground-to-background Activity transition checkpoints the current playback position without pausing background playback;
- Player Show Notes publication is request-generation guarded so a stale Reader load cannot publish into a different preview item;
- focused JVM guards cover idle-vs-playing playback sync policy and latest-request Listening List publication;
- device testing completed without further blocking E6 findings; any later E6 regression is normal bug-fix follow-up unless it contradicts the frozen media ownership/runtime contract.

E6 consumes the frozen Phase B media domain.

Android owns one app-scoped media runtime over the same Core account/session.

Required product scope:

- Listening List and feed filtering;
- playback preparation;
- local or remote source chosen by Core;
- Play/Pause/Stop;
- seek and ±30-second skip;
- playback rate;
- sleep timer;
- chapters/show notes/artwork;
- adding audio to the Listening List asynchronously requests the shared Core's bounded remote artwork probe when no full download is already requested/available; MP3/ID3 uses an adaptive prefix probe (256 KiB initially, at most 8 MiB for the declared tag), while MP4/M4A uses best-effort 1 MiB prefix + 1 MiB tail sampling; successful probe artwork is persisted by Core and propagated through the existing media revision path without delaying the add action;
- playback checkpoints and completion/restart;
- audio focus/noisy-route handling;
- background playback;
- media downloads;
- process-death/relaunch reconciliation;
- Wi-Fi/network policy;
- retention/delete-after-playback;
- Downloaded Data count/size/Delete All Downloads.

Media3/ExoPlayer is the preferred native playback baseline unless E6 uncovers a concrete incompatibility.

### Transfer execution

Core remains authoritative for Requested/Downloaded/Failed/DeleteRequested and policies. Android owns physical transfer execution and its platform task registry.

Do not choose a transfer backend solely by analogy to iOS. E6 must evaluate the current Android options against:

- long-running media transfer behavior;
- network constraints;
- foreground execution requirements;
- cancellation;
- process death/recovery;
- duplicate suppression;
- reliable file finalization;
- Android version behavior from API 29 onward.

Media3 download execution and/or WorkManager/system-native transfer mechanisms are implementation candidates. The chosen backend must report through the existing Core download lifecycle and must not persist a second domain download state machine.

## 18. E7 — MediaSession, System Media and Android Auto

E7 is the Android counterpart to the product purpose of iOS D7, not a port of CarPlay code.

Use one Android media service/session over the E6 playback runtime. MediaSession, system media controls, playback notification and Android Auto are projections/command adapters over that same player and Core-backed media state.

A MediaLibrary-style service/session should expose browse content required by Android Auto without creating an automotive database/cache.

Android Auto browsing uses the current Core-backed Listening List/media read models, not a filesystem scan of downloaded Flutter files.

The Android Auto browse root is the Listening List itself. Its direct children are playable Listening List items. Feeds are not browse nodes and must not become root branches or a second hierarchy level. Feed selection is a filter over that same root item set, using `listeningListFeeds()` only to supply available filter choices and `listeningList(feedId:sort:)` to reload the root contents.

Remote and downloaded media are both valid when Core prepare_playback resolves them.

Initial remote command vocabulary follows the existing media product contract:

- Play;
- Pause;
- Toggle where the Android system maps it;
- skip backward/forward;
- absolute seek where supported.

Do not invent next/previous episode, autoplay or a durable queue merely because Media3 supports them. Those require an explicit product/domain contract.

There remains exactly one native Android player/media runtime per app process.

Initial E7 implementation starts by extending the existing E6 playback service to one `MediaLibraryService` / `MediaLibrarySession`, adding Android Auto manifest discovery and exposing a process-scoped, disposable Core-backed Listening List projection. Headless service startup must restore the existing account/Core session through `AndroidAccountBootstrap`; it must not require `MainActivity` to have run first.

Current E7 implementation status — **complete for sequencing as of 9 October 2026**:

- the E6 service is the single `MediaLibraryService` / `MediaLibrarySession`, still owning the same ExoPlayer and process-scoped playback coordinator;
- both Media3 and legacy `android.media.browse.MediaBrowserService` discovery are declared together with the Android Auto media descriptor;
- the stable/classic automotive root projects direct playable Listening List items and keeps feed data out of the normal browse hierarchy;
- classic Android Auto search narrows by article title or feed title, while custom browse-action feed filtering is capability-gated and omitted when the host reports no custom browse-action support;
- external item selection and legacy `playFromMediaId` resolve through Core `preparePlayback`, retaining local-download preference, remote fallback and Core resume position;
- system media metadata includes article title, feed title, duration, MIME type and Core/remote artwork;
- system seek-back/seek-forward use the product contract of 15 seconds backward and 30 seconds forward; Next/Previous episode commands remain unavailable and E7 still introduces no queue or autoplay semantics;
- external seeks update the shared presentation state and checkpoint through the existing E6 coordinator, while external Stop is reflected back into Flux playback state;
- Core/media revision and Core-session changes refresh the automotive snapshot and notify subscribed browsers through `notifyChildrenChanged`;
- automotive snapshot publication is request-generation guarded so older browse/search/filter work cannot overwrite a newer projection;
- browse and Now Playing artwork are served through local content URIs backed by Core/remote artwork with separate browse and Now Playing fallbacks; cancelled host artwork requests are tolerated so viewport churn does not crash the app;
- Media3 completion status/percentage is projected from Core playback state for compatible classic hosts;
- the development flavor additionally contains the forward-looking Android for Cars App Library media surface while production remains on the stable MediaLibraryService path;
- the development CAL surface uses the same E6/E7 player and Core-backed Listening List, with SearchHeader, feed chips, per-item progress bars, artwork, explicit Now Playing via `MediaPlaybackTemplate`, a direct Now Playing return action and visible marking of the currently loaded item;
- the CAL surface respects host-provided list content limits and records car API/capability diagnostics rather than maintaining a second automotive cache or domain model;
- CAL Beta Features / Car API 9 acceptance on a physical Android Auto host has proven SearchHeader, feed chips, progress bars, direct playback, Now Playing navigation and stable scrolling after artwork-cancellation hardening;
- the repository Android test gate is green after the final E7 Media3/CAL lint fixes.

E7 real-device acceptance is complete. Remaining CAL scrolling performance is treated as non-blocking host/beta presentation behavior unless future testing reveals a reproducible Flux-side regression. Production rollout does not depend on the experimental CAL presentation path becoming generally available.

## 19. E8 — Reserved / no artificial iOS counterpart

E8 has no planned implementation.

Do not create an Android feature merely to mirror the Phase-D numbering or the deferred iOS ActivityKit block.

A future Android-specific capability may occupy E8 only after a distinct product requirement and architecture decision. No current Phase-E release gate depends on E8.

## 20. E9 — Flutter Replacement Completion and Production Acceptance

**Status: E9 COMPLETE / REAL-DEVICE ACCEPTED — production upgrade and Playback Verification v2 accepted on 10 October 2026.**

E9 is a closure phase, not a dumping ground for features that belong in E2-E7.

Current E9 implementation status:

### October 2026 — production upgrade acceptance and playback verification v2

The signed production-identity Flutter-to-native Android upgrade path has already
been exercised successfully on physical hardware in an earlier E9 acceptance
pass. That pass verified the retained production identity, access to the old
Flutter state, native account/settings/media migration and continued operation
after the upgrade. At that time unresolved historical playback positions could
still be explicitly finalized through **Finish with unresolved items**.

The current playback semantics are stricter and more useful. Positive legacy
positions are retried against Core/Miniflux. A confirmed HTTP 404/410 is treated
as terminal stale history only when a complete read-only legacy download scan
proves that no matching local audio file exists. Such entries are shown as old
playback positions that were discarded, and the Playback stage may still finish
green. If a local legacy download exists, if download evidence is incomplete,
or if identity/network resolution fails, the item remains retryable.

Android download discovery now mirrors the iOS production finding that old
absolute secure-storage paths are not sufficient evidence: the reader also scans
the legacy `audio_cache` for validated `audio_<enclosureId>_<timestamp>.*`
files and maps them through the read-only Flutter SQLite enclosure/article
relationship. Flutter files remain read-only and are never deleted by migration.

Because the already-upgraded physical test device had previously used the manual
partial-completion path, Playback Verification v2 reopens only that previously
skipped Playback stage once. It clears neither account/settings/feed/widget nor
download completion state, and Core's existing native playback state still wins.
After the v2 pass the migration summary is surfaced once again; a successful run
sets the v2 completion marker and cannot loop.

This v2 flow was verified successfully on the already production-upgraded
physical Android device on 10 October 2026. The migration completed green and
correctly identified the stale historical playback positions as old/discarded
because no matching local download existed and Miniflux returned confirmed
404/410. That closes the final focused E9 migration-acceptance gap without
requiring a fabricated fresh Flutter state.

Automated tests cover the v2 reopening predicate, durable discarded-ID encoding,
404-without-download discard, download-backed retry behavior, incomplete-download
evidence safety, direct legacy audio-cache discovery and the green migration
summary containing discarded-old-progress details.

### Play production bundle and F-Droid release handoff

Build the production Google Play AAB with `./android/Build/build-app.sh productionBundle <versionCode> <versionName>`. Provide the gitignored `android/productionBundle-signing.properties`, containing `keyAlias`, `keyPassword`, `storeFile` (relative to `android/`) and `storePassword`. The upload key must match the key accepted by the existing Google Play application. The Play upload certificate is not necessarily the installed app signing certificate; this AAB does not validate an APK-side in-place Flutter upgrade. The normal `productionRelease` APK keeps its separate signing contract. Verify the bundle manifest's application ID and versions, upload-signing certificate and Play Console acceptance before release. Do not commit secrets or keystores.

**F-Droid transition (post-E9 distribution work):** Flutter's current F-Droid distribution and signature submission tooling live in `KevinCFechtel/FluxNews` (`.github/workflows/build-and-release.yml`, `.github/workflows/submit-fdroid-signatures.yml`, `.github/scripts/prepare_fdroid_metadata.py`). This is a distinct distribution pipeline, not the Play AAB. The native `Flux` repository still needs its own F-Droid build and publish GitHub Action. That action must use the same canonical release/version inputs as the local Android release script, keep F-Droid signing separate from Play signing, prepare reproducible/offline-compatible metadata and artifacts, and validate an installed signed update over the existing Flutter F-Droid variant before the old pipeline is retired. See [RELEASE_DISTRIBUTION.md](RELEASE_DISTRIBUTION.md) for the authoritative cross-platform release plan.


- Android release versionName/versionCode now accept explicit parameters through `android/Build/build-app.sh <variant> <versionCode> <versionName>` with `--help` documentation; existing CI builds without parameters and the old developmentBundle versionCode-only form remain compatible. Production release signing/version metadata and Play Console upload acceptance remain release-distribution checks rather than migration-implementation blockers;

- the audited E1 FlutterSecureStorage/legacy-state reader now lives in the production source set and remains read-only;
- normal and headless account bootstrap run the same migration preflight before reading native credentials;
- an existing native account wins without reading or changing Flutter state;
- production upgrades with readable Flutter credentials copy URL, API key and complete custom-header pairs into the native Keystore-backed credential envelope;
- unavailable legacy secure storage is treated as retryable rather than as an empty/fresh installation;
- account migration writes non-secret provenance before the native credential copy, so termination cannot leave an unmarked migrated account; failed copies clear the provisional marker and partial native copy while leaving Flutter sources untouched;
- parser/coordinator regression tests cover credential requirements, custom-header extraction, native-wins behavior, retryable unreadable storage and failed-copy cleanup;
- the E9 post-sync adapter now imports compatible Core policy/media settings and positive per-feed Open in Miniflux overrides exclusively for the migrated account. Separate completion flags make a missing feed retry on subsequent successful syncs; explicit native/Core state retains precedence;
- E9 playback imports positive article-keyed positions from Flutter SharedPreferences with secure-storage fallback; zero is omitted and Core owns unique-enclosure resolution, precedence and import outcomes. Ambiguous identity, transient failures and any record backed by a local legacy download remain retryable;
- E9 reads the read-only Flutter SQLite enclosure→article relationship and uses a targeted Core/UniFFI Miniflux article fetch to hydrate historical read articles and matching audio attachments before download adoption. For playback, Core now reserves a `false` restore result for confirmed HTTP 404/410; identity mismatch or non-unique audio is an error rather than stale evidence. A confirmed 404/410 with no matching local legacy download is terminal stale progress and is visibly discarded without failing the migration. Successfully imported native state wins and legacy source files remain unchanged;
- E9 media analysis now probes the actual audio bytes, including migrated `.audio` files. A separate durable one-time repair pass re-extracts missing embedded artwork, duration and chapters from previously imported Flutter downloads without changing downloaded/playback state, then marks metadata repair complete only after successful processing; Support Diagnostics report scan and recovered-artwork counts;
- E9 download migration logs summary counters and missing/failed enclosure IDs to Support Diagnostics under `migration.downloads` at Info/Warning level (no file paths, URLs or secrets), allowing troubleshooting after a successful sync without enabling Debug Logging;
- E9 media migration validates legacy enclosure identity against the cloned read-only SQLite catalog and accepts verified source audio from either valid stored path metadata or the legacy `audio_cache` filename convention used by Flutter. It copies into a disjoint native media root using a staged file and only then asks Core to adopt it. Existing Core downloads win; missing enclosures remain retryable; original Flutter media is never removed;
- E9 local presentation follow-up now imports compatible navigation visibility, article-count/read-on-scroll/remove-on-read, reader-opening and swipe semantics, and Android floating-toolbar actions using atomic native-presence-first DataStore writes;
- startup category/feed imports are catalog-validated and remain independently retryable until the first successful sync contains the requested ID;
- Flutter global widget scope/read-filter/sort values now seed only unconfigured native widgets; an existing per-widget native configuration remains authoritative. Obsolete item-limit/styling and widget-specific Miniflux-open preferences remain retired;
- E9 finalization now records a durable `completed` or `completed_with_skipped_items` status, with the original unresolved playback/download reasons preserved separately. Manual partial finalization atomically stores skipped details, stage markers and acknowledgment; ordinary `Done` sets the verified completion status. Successful imports are never discarded, and the UI marks skipped stages as completed with skipped items rather than claiming a full import;
- Users may explicitly finish with unresolved media only after the settings/catalog steps have completed and the playback/download attempts have returned recorded retry reasons. Successfully imported positions/files are retained; pending media retries are then waived and the dialog is acknowledged. Without confirmation the existing retry-on-sync and dialog-on-relaunch behavior remains unchanged;
- E9 presents an optional, non-blocking first-upgrade migration dialog after account restoration, using persisted completion markers for account, local/Core settings, feeds/start view, playback, downloads and widgets. It shows only categorical statuses (no URLs, secrets, filenames or article titles), offers an explicit sync action, remains retryable after dismissal, and is permanently acknowledged only once all stages complete;
- the signed production-identity physical Flutter-to-native upgrade path has been accepted on real hardware, including retained legacy-state access and coexistence with untouched Flutter source data;
- the versioned Playback Verification v2 recheck has been accepted on the already-upgraded physical installation and replaced the earlier manual skip result with the new automatic stale-404 classification;
- canonical Rust + Android + affected Apple regression CI remains mandatory for later shared Core/UniFFI changes, but there is no remaining E9 physical migration-acceptance blocker.

By the start of E9, the productive native Android feature set must already include Settings, backup/restore, localization, logging/support diagnostics, widget configuration, media/downloads and system integrations.

E9 performs:

- full current-Flutter behavioral/migration gap audit;
- verification that deliberately retired/replaced Flutter behavior remains retired;
- completion of the production Flutter-to-native migration coordinator using the E1-proven readers;
- Android-specific legacy settings mapping not already consumed earlier;
- legacy widget/default/component migration closure;
- legacy playback/download migration closure;
- production signing/package/manifest validation;
- upgrade installation over the latest production Flutter build;
- first launch and migration interruption/retry tests;
- post-upgrade sync and offline tests;
- final feature/accessibility/localization audit;
- canonical Rust + Android + affected Apple regression gate;
- confirm productive UniFFI/Core execution on physical replacement hardware (satisfied by the accepted E9 production-upgrade run; the targeted E1-B smoke remains optional diagnostic coverage);
- physical production-upgrade acceptance (completed, including the later Playback Verification v2 semantic recheck on the already-upgraded production-path device).

Flutter is not a parity checklist. E9 imports only retained semantic state and validates only retained/current product capabilities.

## 21. Localization and user-facing baseline

Native Android ships the same retained production language set as Phase D:

- English;
- German;
- Spanish;
- Galician;
- Dutch;
- Tamil;
- Turkish.

Use Android-native resources/tooling. Flutter ARB files may be translation/reference evidence during migration but are not runtime localization sources.

Active strings must have complete coverage, including plural/format compatibility tests appropriate to Android resources.

## 22. Support diagnostics baseline

Android must provide a normal user-facing Support Diagnostics destination equivalent in product purpose to completed D9-H:

- Debug Logging toggle;
- retained record count;
- structured Log Viewer;
- newest-first entries with timestamp/level/category/message;
- text search and level filtering;
- refresh;
- per-record copy;
- privacy-sanitized export through native sharing/file flow;
- confirmed Clear Logs;
- concise privacy/retention explanation.

Normal Info/Warning/Error support records remain available without Debug Logging; Debug/Trace retention is gated by the preference.

Do not restore legacy Clear Logs on Start.

Android logging may use platform logging as an additional sink, but there must be one app support-log model rather than parallel authoritative log databases. Core diagnostics are bridged/redacted through the native support path.

## 23. Testing and acceptance strategy

Every phase uses the smallest relevant test surface plus regression gates for touched shared code.

### Shared/Core gate

When Core/UniFFI is unchanged, run the canonical Rust workspace tests at meaningful integration checkpoints.

When Core/UniFFI changes, all Rust workspace tests and affected native Apple gates must remain green before accepting the shared change.

### Android gates

Build a repository-owned Android test path that can cover:

- JVM unit tests for presentation/policy adapters;
- instrumented/emulator tests for Android APIs and lifecycle where needed;
- physical-device tests for performance, Keystore/migration, notifications/background work and media;
- Android Auto acceptance for E7;
- signed production-identity upgrade tests for E1/E9.

Do not claim a migration, production upgrade, ABI, TLS behavior, background behavior or real-device media behavior from a unit test alone.

### Accessibility

Phase acceptance includes Android accessibility semantics, Dynamic Type equivalent/font scaling, touch targets, TalkBack behavior and reduced-motion/system preferences where applicable.

## 24. Risk register and mandatory early proofs

### Critical — Production signing/update identity

The production application ID and compatible signing key are mandatory for in-place replacement. E1 must prove the release path before deep implementation.

### Critical — Legacy secure-storage extraction

The native production build must be able to recover the retained Flutter secure-storage values using the installed app's existing Keystore-backed material. This cannot be assumed from source inspection; E1 requires a physical production-identity upgrade spike.

### Closed — Rust Android TLS/platform verifier

Closed by E1-C. The pinned verifier is integrated, its Android initialization runs before any Core network access, and the required trust behavior — system/public CA, invalid certificate rejection and user-installed CA — is proven on API 29 and on a current Android release.

### High — UniFFI Android ABI/packaging

The shared API is mature, but Gradle/ABI packaging is not yet implemented. E1 closes this gap before product work.

### High — Legacy media files and download finalization

Migration must resolve canonical enclosure identity and move/copy verified files into the new native/Core media root without destructive legacy conversion.

### High — Compose Timeline performance

The iOS UIKit history is not evidence that Android Compose will fail. E3 requires real measurements before renderer changes.

### High — Background execution and credentials

WorkManager may run after process death and under device restrictions. Credential/Core bootstrap must remain safe and bounded without requiring a foreground Activity.

### High — Single media runtime across UI/service/Android Auto

E6/E7 must avoid duplicate player/Core ownership when the media service outlives or starts without the Activity.

### Medium — Existing widget instances

Production widgets may depend on the legacy provider component identity. Preserve or deliberately migrate that component path rather than silently orphaning installed widgets.

### Medium — OS backup interaction

Native data, legacy data, Android Auto Backup and explicit Config Backup have different semantics. E1 defines exclusions before production data exists in new paths.

## 25. Real Core gaps versus platform integration gaps

The repository-first audit found no known release-baseline product-domain gap that requires a new Kotlin domain or a Phase-A/B rewrite.

Known work is primarily platform integration:

- Android UniFFI build/package/load path;
- TLS platform-verifier initialization/proof;
- Android process/Core execution ownership;
- credential/preference adapters;
- WorkManager/Notification/widget adapters;
- Media3/transfer/Android Auto execution;
- legacy Android extraction/migration.

Potential narrow shared changes are allowed only when implementation proves them necessary. Examples include:

- an additive UniFFI/native initialization entry point required by the Android TLS verifier;
- a genuinely missing typed projection needed by both native clients;
- a binding compatibility fix required for a retained Android ABI.

Use the escalation format from the frozen architecture:

    Contract requires X.
    Existing API/implementation guarantees Y.
    X and Y conflict because Z.

Do not label an Android framework adapter as a Core gap.

## 26. Intentionally open implementation details

The following remain implementation choices inside the frozen boundaries:

- exact development application ID;
- final Kotlin package/namespace;
- exact Gradle plugin versions at implementation time;
- exact Gradle task layout for Rust cross-compilation and binding generation;
- whether armeabi-v7a remains a shipped ABI;
- exact Android Keystore-backed credential envelope format;
- exact app-private Core/media/log/widget-projection directory names;
- exact adaptive navigation components used by the current Material library;
- exact Compose image-loading implementation;
- exact E6 physical transfer backend;
- exact notification channel grouping/names;
- exact Glance/RemoteViews layout implementation;
- exact physical device matrix beyond the required API-29 floor plus a contemporary Android device.

These decisions must not change Core/domain ownership.

## 27. Frozen Phase-E decisions

The following are decided unless implementation finds a concrete contradiction:

- Kotlin + native Android;
- Jetpack Compose as the initial productive UI baseline;
- adaptive phone/tablet/foldable design from window environment;
- UniFFI as the only app/Core binding;
- no second Kotlin domain or Miniflux layer;
- one process-scoped Core/account session;
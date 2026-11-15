# Post-Replacement Stabilization and Store-Readiness Plan

> **Status: IN PROGRESS — A1–A3 owner-accepted 18 October 2026; B2 remains open**
>
> **Verified code baseline:** `main` at `2edc6537aebac35260d35f4dcbcab8dcfc7a0ae9`
> (16 October 2026; [Apple CI #167](https://github.com/KevinCFechtel/Flux/actions/runs/38934397341)
> passed). Original plan baseline was `9bd6ea9` (11 October).
> C3.1–C3.7 are **merged**; C3.8 functional and B1 Sandbox gates
> are **owner-accepted (17 October 2026)**. PR #61 is merged. A1–A4, B1, C1, C2 and C3 are accepted or completed as
> described below; B2 and release track R remain open. Source/CI evidence is not
> a device-acceptance or App Store submission claim.
>
> **Relationship to existing contracts:** `ARCHITECTURE_DECISIONS.md` and the
> frozen Phase B/C/D/E and `MOBILE_PRODUCT_SEMANTICS.md` contracts retain their
> existing authority. This plan records focused post-E9 corrective and product
> follow-up work; it does not reopen accepted Flutter-to-native migrations.
> `RELEASE_DISTRIBUTION.md` remains the authority for release-script interfaces,
> signing and publication.

## 1. Explicit product decision: macOS starts fresh

**FluxNews for macOS has not been released to users.** Existing macOS data are
limited to the developer's local machine. The owner explicitly accepts losing
those local development data when sandbox support is enabled.

Therefore:

- **Do not implement a macOS data migration**, `container-migration.plist`,
  copy from the former unsandboxed `Application Support` directory, or a
  fallback/compatibility storage path.
- A clean sandbox-container initialization is the intended behavior. Treat an
  empty database, cache, download directory and freshly configured credentials
  on the developer machine as acceptable.
- Test a first launch with fresh account setup, sync, media downloads, playback,
  widget sharing and restart persistence *inside* the sandbox.
- Do not preserve developer Keychain entries merely to avoid entering account
  credentials again. Do verify the new sandboxed app can **save and subsequently
  read** credentials reliably.
- Keep the existing production bundle/App Group identifiers as required by
  the release contract unless an explicit signing/provisioning constraint
  requires a separate, reviewed change.
- The existing Developer ID signing/notarization script and the proposed Mac
  App Store export are different distribution paths. Do not assume a Developer
  ID app can be upgraded into the App Store app or that such a migration is
  required before first release.

The no-migration decision is **macOS-specific**. It must not weaken the
already accepted iOS/Android in-place Flutter-to-native upgrade guarantees.

## 2. Planned work order and gates

| ID | Priority | Target | Status on `main` (16 Oct) | Required remaining gate | Depends on |
| --- | --- | --- | --- | --- | --- |
| A1 | P0 | iOS + macOS | **Owner-accepted 18 Oct 2026** | Closed by owner sign-off; previously listed runtime scenarios are not independently evidenced | — |
| A2 | P0 | Rust + Apple | **Owner-accepted 18 Oct 2026** | Closed by owner sign-off; no independent lifecycle/leak-test evidence asserted | — |
| A3 | P0 | Android | **Owner-accepted 18 Oct 2026** | Closed by owner sign-off; no independent runtime network-transition evidence asserted | — |
| A4 | P0 | CI | **Implemented and Rust CI green** (PR #62 merged); blocking `cargo fmt --check` | Required-check branch protection remains a separate repository setting to verify if desired | — |
| B1 | P0 before Mac App Store release | macOS | **Owner-accepted 17 Oct 2026** after successful Mac testing; entitlements/verifier/installer implemented (#38, #53) | Closed by owner sign-off; distribution validation belongs to R | A1/A2 validation as applicable |
| B2 | P0 before F-Droid workflow | Android/F-Droid | No source-build/scanner gate proven | Reproducible build, scanner, signing/upgrade feasibility | A4 recommended |
| C1 | P1 | Android | **Owner-accepted 17 Oct 2026**; Android localization closed for this roadmap | Weblate is a separate future cross-platform workstream; subsequent localization defects are bugs | — |
| C2 | P1 | Android | **Owner-accepted 17 Oct 2026**; native add-feed/add-category flows and policy tests implemented | Closed by owner sign-off; subsequent defects are regressions | — |
| C3 | P1 | macOS | C3.1–C3.8 merged; **C3.8 owner-accepted 17 Oct 2026** (PR #61 merged) | Closed; subsequent defects are regressions | — |
| C4 | P2 | Shared/clients | Selective maintenance | Evidence-driven tasks only | Earlier relevant gates |
| R | Release track | All platforms | Unified release layer planned | Shared CLI, Play/iOS paths; macOS after B1, F-Droid publishing after B2 | B1 for macOS; B2 for F-Droid publishing |

P0 denotes work to resolve before the **relevant release**, not an assertion that
all platforms must block each other's releases. Where independent, use
separate focused PRs and run only the affected platform gates plus Rust gates.

## 3. A — Stability, correctness and regression coverage

### A1 — Apple App Transport Security and HTTP-only resources

**Implemented:** Both Apple host Info.plists set
`NSAppTransportSecurity/NSAllowsArbitraryLoads = true` and have structural
tests. This is deliberately broad because arbitrary feed media uses both
URLSession and AVFoundation; see [APPLE_HTTP_MEDIA_ATS.md](APPLE_HTTP_MEDIA_ATS.md)
for the security trade-off and App Store rationale. Widget ATS is unchanged.
**Acceptance (18 October 2026):** Owner marked A1 accepted. The previously listed iOS/macOS HTTP-only image/artwork, streaming, download and redirect checks remain historical test guidance, not independently verified evidence.
The points below preserve the original verification contract.

**Original implementation/validation scope:**

1. Establish controlled HTTP-only test endpoints for an article image, podcast
   enclosure download and podcast playback/streaming. Check both iOS and macOS.
2. Record what actually works/fails and which Apple API handles each request.
   Also check redirects where relevant. Distinguish HTTP-only content from
   a plain-HTTP Miniflux server address.
3. Define a narrow, defensible ATS policy. The media-only AVFoundation exception,
   if used, **does not cover URLSession**; do not incorrectly treat
   `NSAllowsArbitraryLoadsForMedia` as a universal fix.
4. Prefer HTTPS when available. If supporting arbitrary HTTP-only feed media is
   necessary, document the scope and privacy/security trade-off of the
   appropriate exception, and test the exact behavior. Preserve the explicit
   unencrypted Miniflux-server warning; do not silently normalize insecure
   account connections.
5. Add practical regression coverage (fixture/integration test or explicit
   device acceptance where an automated test is not possible).

**Done when:** iOS and macOS load or deliberately reject each tested HTTP-only
image, streaming and download case as documented; HTTPS still works; no broad
ATS exception is introduced without an explicit reason.

### A2 — Rust UniFFI EventSubscription and Apple lifecycle

**Implemented in part:** `core/crates/flux-uniffi/src/lib.rs` now has an
idempotence-compatible `Drop for EventSubscription` fallback in addition to
explicit `unsubscribe()`. This removes the original missing-Drop finding.
**Acceptance (18 October 2026):** Owner marked A2 accepted. The previously listed Apple listener lifecycle and memory-retention checks are historical validation guidance; independent evidence for them is not asserted. Source presence is not leak-test evidence.

**Original implementation/validation scope:**

1. Map all macOS/iOS `subscribeEvents` and `eventSubscription` ownership paths,
   including newsreader, media runtime, widgets, account changes and resets.
2. Explicitly call `unsubscribe()` before replacing/releasing the subscription
   on Apple; avoid races with in-flight event callbacks. Consider Rust `Drop`
   as a defensive fallback, with tested idempotence, rather than relying on
   garbage collection or assuming assigning `nil` unregisters listeners.
3. Remove unnecessary strong listener -> Core references and use
   generation/lifecycle guards to discard stale callbacks.
4. Validate account replacement, local rebuild, detach, widget refresh and
   repeated reopen: old listeners stop receiving events and old Core handles
   become releasable. Use memory diagnostics to distinguish a real SQLite
   retention issue from the currently unverified hypothesis.
5. Preserve Android's explicit unsubscribe/close behavior.

**Done when:** lifecycle and repeated-attach tests demonstrate one intended
listener per owner, no stale callbacks, no regressions to sync/widgets/media,
and no retained retired Core session.

### A3 — Android WorkManager constraints when download policy changes

**Implemented:** `AndroidMediaTransferCoordinator.reconcile()` detects
changed policy tags for existing requests and uses WorkManager `updateWork()`
instead of relying on `ExistingWorkPolicy.KEEP` alone. Tests in
`AndroidMediaTransferPolicyTagsTest.kt` cover policy changes and unchanged
constraints. **Acceptance (18 October 2026):** Owner marked A3 accepted. The previously listed queued/running download and real Wi-Fi/mobile policy-change scenarios remain regression guidance, without an independent runtime-test claim.

**Original implementation/validation scope:**

1. Add a reproducible test: queue download on unmetered-only; while pending,
   change to any network; verify the download becomes eligible on mobile data.
   Test the reverse policy change too.
2. Reconcile the pending work *when effective constraints change*. Do not
   replace every WorkRequest unconditionally during frequent reconciliations.
   Make sure running downloads are not repeatedly cancelled, duplicated or
   restarted due only to state refresh.
3. Preserve cancellation, progress and Core-owned download state; cover queued,
   running and completed work separately.

**Done when:** policy changes affect pending transfers immediately and
running/completed transfers retain correct semantics on both network types.

### A4 — Dedicated Rust regression gate in CI

**Implemented:** `.github/workflows/rust.yml` runs the separate Rust workspace
tests and Clippy on Core/workflow changes, plus a blocking formatting audit on
Rust 1.99.1. The workflow verifies the installed compiler version explicitly
and uses the committed lockfile for tests and Clippy. Required-check branch
settings and strict warning handling remain repository-administration choices.

**Original implementation/validation scope:**

1. Add one shared, native-host Rust job/workflow triggered by changes to
   `core/**` and its own workflow, and required for relevant PR checks.
2. Run at least:
   - `cargo fmt --manifest-path core/Cargo.toml --all --check`
   - `cargo test --manifest-path core/Cargo.toml --workspace`
   - `cargo clippy --manifest-path core/Cargo.toml --workspace --all-targets`
3. Pin the intended toolchain and cache safely. Check whether strict Clippy
   warning-as-error can be enabled without unrelated baseline cleanup; do not
   silently enable a gate that fails on existing warnings.
4. Keep native Apple/Android regression workflows as separate platform gates.
   Avoid re-running identical host-Rust tests in each Apple and Android job.

**Done when:** a PR that changes Rust fails on a Rust regression in CI
independently of UniFFI compilation, while native tests remain intact.

## 4. B — Prerequisites for distribution

### B1 — Enable the macOS App Sandbox before App Store export

**Owner-accepted 17 October 2026:** PR #38 added the host
Sandbox entitlements and sandbox-local media paths. PR #53 added
`verify-sandbox.sh`, signed development build validation and protected
`install-local.sh` staging; [Apple CI #164](https://github.com/KevinCFechtel/Flux/actions/runs/38924332033)
passed. The project owner reported successful macOS tests and explicitly closed both B1 and C3.8 on 17 October 2026. This is owner-reported sign-off, not independently captured evidence for each signed fresh-container check. Mac App Store archive/export and Transporter verification remain part of release track R. See [MACOS_SANDBOX_ACCEPTANCE.md](MACOS_SANDBOX_ACCEPTANCE.md).

The implementation-oriented steps below are historical requirements; only
items not yet proven by the signed-app checklist remain release-open.

**Current source baseline:** `apple/macos/FluxNews/FluxNews.entitlements`
contains the host App Sandbox, outbound network and App Group capabilities.
The existing `apple/macos/Build/release-developer-id.sh` Developer ID path is separate
from future Mac App Store signing and does not verify store eligibility.

**Implementation:**

1. Enable sandbox for the macOS **host app** and verify it is present in the
   final signed entitlement set; preserve/verify the widget sandbox and the
   existing application-group capability.
2. Add the required outbound `com.apple.security.network.client` entitlement
   for Miniflux, images, podcasts and downloads. Review any other capabilities
   against actual native operations rather than adding permissions speculatively.
3. Audit configuration backup export/import, user-selected file dialogs,
   temporary files, downloads, app support/cache, file permissions and
   App Group/widget data exchange. Add the narrow user-selected file
   read/write entitlements if testing shows they are needed.
4. Verify provisioning/signing matches the App Group for Mac App Store
   distribution. **Do not equate Developer ID with Mac App Store signing.**
   Retain the existing Developer ID path until intentionally changed, and
   test its sandbox-compatible behavior independently if it remains supported.
5. Start the sandboxed app from a **fresh account**; initialize all Core
   persistent/cache/media directories in the sandbox, sign in again, sync,
   download, play, use widget, export/import a backup and restart.
6. Document deliberate loss of the developer machine's old unsandboxed data.
   **No migration, `container-migration.plist`, file-copy shim or backwards
   compatibility path is in scope.**
7. Only after sandbox acceptance, implement macOS archive/export/Transporter
   scripts according to `RELEASE_DISTRIBUTION.md`.

**B1 runtime gate done when:** signed development app, fresh sandbox install
and relaunch function end-to-end; Core data, credentials, media and App Group
persist; file dialogs, widgets, login item and background operation work; no
unresolved sandbox denials remain. **Separate R gate:** only *after* B1,
produce and validate a correctly provisioned Mac App Store archive/export.
Mac App Store export is not a prerequisite to closing B1; no legacy macOS
data migration is required.

### B2 — F-Droid reproducibility/scanner feasibility before publishing

**Evidence:** Android resolves the pinned
`rustls-platform-verifier-android` Maven AAR by calling `cargo metadata`
during Gradle settings evaluation; JNA is also used as an AAR. These are
risks to audit, **not proof** of F-Droid scanner rejection.

**Implementation:**

1. Review current F-Droid policy, build-server toolchain and source/repo
   requirements against pinned Android Gradle, Rust, Cargo/NDK, JNA and
   rustls-platform-verifier components.
2. Run a representative source build and F-Droid scanner/metadata validation
   using the intended build environment, recording exact failures.
3. Ensure all required Cargo and Gradle dependencies are resolved by an
   approved, reproducible path. Test `cargo metadata` under restricted/offline
   build conditions after dependency preparation. Use vendoring only if
   needed and compatible with the final distribution model.
4. Verify provenance/allowability of both included AAR/native components and
   whether any prebuilt library must be compiled from source.
5. Preserve the existing F-Droid package identity, signing/update guarantees
   and source metadata. Verify a signed update over the Flutter F-Droid app;
   do not reuse Play signing by assumption.
6. **Only after passing this feasibility gate**, implement the native F-Droid
   prepare + build/verify + separately triggered publish workflow using the
   shared release scripts.

**Done when:** repeatable F-Droid-style build and scanner pass, dependencies
and source requirements are documented, and Flutter-to-native signed update
compatibility is demonstrated before publication automation replaces legacy.

### B2.1 preliminary repository audit (18 October 2026)

**Status (18 October 2026): native recipe build and scanner passed twice** ([run 39140681750](https://github.com/KevinCFechtel/Flux/actions/runs/39140681750), [run 39145172707](https://github.com/KevinCFechtel/Flux/actions/runs/39145172707)), on *different source SHAs*. This is feasibility evidence only; same-SHA bitwise reproducibility, rustls embedded-prebuilt-AAR provenance, signing and signed Flutter-to-native upgrade remain **unverified**. JNA 5.19.1 is an upstream Maven Central Android AAR licensed under Apache-2.0/LGPL-2.1-or-later. The Cargo.lock-pinned rustls-platform-verifier-android **0.1.1** crate embeds a Maven AAR; whether distributing that prebuilt binary satisfies F-Droid policy requires separate confirmation. The scanner ignores only android/settings.gradle.kts because the version-2.4.5 scanner treats the computed *local* Cargo Maven path as a potentially unapproved remote Maven URL; this exception does not grant permission to ship the AAR. Candidate metadata is now prepared offline by fdroid/prepare_native_recipe.py from android.properties and exact commit SHA; historical recipes, allowed signing keys and CurrentVersion remain unchanged. No official F-Droid submission is authorized.

- `android/settings.gradle.kts` runs `cargo metadata` at Gradle settings evaluation and resolves a Maven AAR bundled with the pinned `rustls-platform-verifier-android` Cargo crate. Verify availability under F-Droid's prepared/offline build environment and source/provenance rules.
- `android/app/build.gradle.kts` declares `net.java.dev.jna:jna:5.19.1@aar` and `rustls:rustls-platform-verifier:...@aar`; audit both against current F-Droid scanner and source-build requirements before changing dependencies.
- `android/Build/build-uniffi.sh` compiles Rust shared libraries for `arm64-v8a` and `x86_64`. The legacy `FluxNews` F-Droid metadata/signature workflow handles `x86_64`, `armeabi-v7a` and `arm64-v8a` separately with version-code offsets +1/+2/+3. Compare existing fdroiddata recipes and decide how native ABI coverage and version codes can transition safely.
- The old `FluxNews/.github/workflows/submit-fdroid-signatures.yml` prepares developer signatures and metadata; `prepare_fdroid_metadata.py` enforces `AllowedAPKSigningKeys` and `AutoUpdateMode: None`. Do not copy old Flutter-specific recipes verbatim.
- Next gate: retrieve actual fdroiddata metadata, record existing signing fingerprints/version codes and build recipe; run representative F-Droid-style build plus scanner, then validate signed upgrade on device. No F-Droid compatibility or reproducibility claim yet.

## 5. C — Product parity and quality improvements

### C1 — Android localization

**Status (16 October): source extraction and the German catalog progressed
through PRs #44–#47.** The final documented German catalog covers 500
translatable base entries (including 11 plurals); the additional five locales
are intentionally awaiting reviewed Weblate translations. Remaining
unmapped/dynamic messages and actual alternate-locale device behavior have not
been fully signed off. Historic scan findings are tracked in
[ANDROID_LOCALIZATION_AUDIT.md](ANDROID_LOCALIZATION_AUDIT.md); do not confuse
the source-level audit or green CI with runtime or Weblate completion.

Extract user-visible Android text into resources (including settings, readers,
navigation, download UI, notifications and widgets). Cover the **seven target
languages specified by the mobile product contract**, with locale-sensitive
pluralization, dates and accessibility labels. Resolve translation ownership
and review; do not present unreviewed machine translations as finished.

**Done when:** all supported languages are selectable by Android locale,
there are no substantive untranslated/hard-coded UI surfaces and targeted
locale/UI tests pass.

### C2 — Android feed and category creation

**Implemented in current source; practical closeout open.**
`AndroidFeedCreationDialog.kt` exposes feed discovery/selection and category
creation through Core/UniFFI, with URL/duplicate validation and localized
failure messages. `AdaptiveAppShell.kt` refreshes navigation, requests sync
and selects created entities; `AndroidFeedCreationPolicyTest.kt` covers
validation and errors. Verify success, duplicate/failure, sync and restart
on a device/emulator before marking C2 accepted. Do not rebuild these flows
solely because the original roadmap described them as planned.

**Done when:** feeds/categories can be created from the Android UI, appear in
navigation after success and survive sync/restart; failure and duplicate
cases are handled.

### C3 — macOS feature-parity completion (approved scope)

**Implementation / acceptance status (17 October):** C3.1–C3.7 were merged via PRs #49–#52.
[Apple CI #167](https://github.com/KevinCFechtel/Flux/actions/runs/38934397341)
passed on combined `main` `2edc6537`. The project owner accepted C3.8 real-Mac testing and B1 on 17 October 2026. PR #61 has since been merged into `main`.
See [MACOS_C3_FEATURE_PARITY_ROADMAP.md](MACOS_C3_FEATURE_PARITY_ROADMAP.md).

**Decision (12 October 2026):** Functional parity with iOS/Android is the
default; macOS retains native menu-bar/window controls rather than copying
mobile UI layouts. **Bulk feed preferences, scope-wide Mark All as Read and
Mark All as Read & Next are explicitly in scope**, not optional follow-ups.

The controlled source-based inventory, order of work, per-PR quality gates and
real-Mac acceptance checklist are in
[MACOS_C3_FEATURE_PARITY_ROADMAP.md](MACOS_C3_FEATURE_PARITY_ROADMAP.md).
Work packages cover: scope bulk-read and Starred filter; multi-feed editing;
download totals, cancellation, policy and retention; diagnostics/redaction;
HTTP account warning, About and player 15/30-second controls; background-sync
recovery; locale/accessibility and functional acceptance.

**Dependency clarification:** C3 feature code can be developed/tested before
B1. **B1 has been closed by project-owner acceptance on 17 October 2026.** Mac App Store signing/export/Transporter validation remains a separate release-track gate. Do not add a macOS migration.

**Done when:** accepted C3 features are tested and merged, current macOS
Apple CI is green, real-Mac functional acceptance is recorded, Core remains
authoritative, and any explicit deferrals are documented.

### C4 — Focused follow-up technical debt (not release blockers by default)

- Audit `REMOTE_WORKERS = 1` and unbounded event mailboxes with actual latency/
  memory evidence; don't increase concurrency blindly or drop correctness events.
- Consider a download-worker shared OkHttp client, resumable transfers and
  better foreground notification behavior only if separately justified.
- Track Swift 6 strict concurrency migration as its own measured effort.
- Review `SavedMedia` UniFFI callers and the Phase-B frozen domain semantics.
  Removing unused outward-facing functions must not remove needed Core
  persistence/retention/optional sync behavior without a deliberate contract
  decision.
- Reconcile outdated article-image loading and Android network-client statements
  in architecture/phase docs, and remove obsolete workflow branch filters.
- Treat deprecation warnings as maintenance unless the target SDK or runtime
  demonstrates an actual break. Do not reopen the completed file-splitting work.

## 6. Validation and delivery discipline

Each focused PR must identify its baseline, affected contracts, changed files,
validation actually run and known remaining risks. Prefer targeted unit and
integration coverage before UI/device gates; never infer success merely from
code inspection. For cross-platform changes run the Rust checks and relevant
Apple/Android checks. For network, playback, storage, app signing and sandbox
changes include real-device or signed-artifact acceptance as appropriate.

**Sequencing with release work:**

- A1/A2/A3: implementation work exists; close actual per-platform runtime and
  lifecycle regression gaps before the corresponding release. A4 Rust tests/
  Clippy exist, but formatting is not yet a blocking check.
- B1 must finish **before** the macOS App Store build/export deliverable
  described in `RELEASE_DISTRIBUTION.md` section 7.
- B2 must finish **before** the native F-Droid publication workflow described
  in `RELEASE_DISTRIBUTION.md` section 5.
- Existing iOS/Android migration acceptance remains closed; no additional
  Flutter migration project is created.
- C1/C2 are explicit post-E9 Android product work, not claims that the
  historical E9 replacement-acceptance decision was never completed.
- No release script or workflow may publish by default.

## 7. Plan completion

This follow-up is complete only when P0 fixes are tested and merged, the macOS
sandbox passes a fresh-install acceptance without a migration, F-Droid build
feasibility is demonstrated, and the accepted C1/C2/C3 items are either
implemented with tests or explicitly deferred as separate decisions.
The separate release/distribution acceptance criteria still live in
`RELEASE_DISTRIBUTION.md`.

## 17 October 2026 — C1 owner acceptance and Weblate scope

The owner considers Android localization (C1) complete for this roadmap. Weblate integration and further translations will be tracked separately as a cross-platform effort for all apps, rather than as a remaining Android C1 gate. Subsequent defects in existing Android localization are handled as bugs.

## 17 October 2026 — C2 owner acceptance and merged PR reconciliation

The project owner accepted Android C2 (feed and category creation) on 17 October 2026. The implemented flows are considered complete for this roadmap; subsequent issues are tracked as regression bugs rather than reopening C2. This is owner-reported acceptance, not a separately attached device test protocol.

PR #61 (macOS parity, listening list and player fixes), PR #63 (C1 owner acceptance) and PR #64 (Android navigation action placement) have been merged into `main`. PR #62 implemented the blocking Rust formatting gate and was also merged. Remaining planned work is B2 (F-Droid feasibility/build/scanner/signing), release track R (unified release tooling and distribution validation), and separately scoped cross-platform Weblate integration. Historical descriptions of earlier validation gates remain as background, not as a reopening of accepted items.

### B2 implementation branch (18 October 2026)

Branch `feat/b2-fdroid-native-preparation` introduces opt-in `FLUX_ANDROID_INCLUDE_ARMV7=1` for the Rust UniFFI build (`armeabi-v7a` / `armv7-linux-androideabi`). Default Android builds remain unchanged. This is preparation only, not proof of successful armv7 compilation or F-Droid compliance. The dual-signature F-Droid release workflow, metadata migration, reproducibility and device upgrade tests remain pending. Do not publish or merge until validated.

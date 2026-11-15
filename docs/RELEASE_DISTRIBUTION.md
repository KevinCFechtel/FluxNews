# Unified Release and Distribution

> **Status: PLANNED FOLLOW-UP / REPLACEMENT IMPLEMENTATION ALREADY COMPLETE**
>
> This document defines the next repository-level release/distribution work after
> the completed native macOS, iOS/iPadOS and Android replacement. It does not
> reopen product implementation, migration acceptance, or frozen architecture.
> The goal is to make release preparation predictable and consistent across all
> native apps while preserving each store's real distribution model.

## 1. Goals

Create one coherent release-scripting model across Android, iOS and macOS.

The release layer should:

- expose consistent version/build-number inputs;
- separate local build/test concerns from signed distribution preparation;
- validate package/bundle identifiers, versions, embedded extensions and signing;
- put final artifacts in predictable `dist/` locations;
- fail early on missing signing configuration or identity mismatches;
- be callable locally and from GitHub Actions without duplicating release logic;
- keep secrets, keystores, provisioning material and App Store credentials out of Git;
- allow CI to build release artifacts when useful, without making CI artifact
  publication the primary Apple distribution mechanism.

Platform-specific store requirements remain explicit. "Unified" means a common
interface and ownership model, not one generic script that hides important
differences between Gradle, Xcode, Play, F-Droid and App Store Connect.

## R1 implementation — production-first defaults (17 October 2026)

The existing platform build scripts now default to production **release build configurations**, not debug configurations. Debug/development identities require explicit arguments. This does **not** mean that a normal build publishes to a store, nor that every release-configured artifact is store-signed.

- Android: `android/Build/build-app.sh` defaults to `productionRelease` (APK). Use `developmentDebug` explicitly for debug and `productionBundle <versionCode> <versionName>` for a signed Play AAB.
- iOS: `apple/ios/Build/build-app.sh` defaults to the production-identity `Upgrade Test` configuration; `developmentDebug` selects Debug. `apple/ios/Build/archive.sh` and `export-appstore.sh` default to the production identity; `developmentRelease` remains explicit.
- macOS: `apple/macos/Build/build-app.sh` defaults to the Release configuration; `CONFIGURATION=Debug` opts into debug. `--build-number N --version-name V` overrides the version for normal builds. Its existing `DEVELOPMENT_SIGNING` behavior is unchanged; store-signed distribution uses the separate archive/export scripts.

The shared entry point is now `bash Build/release.sh`. Examples:

```bash
bash Build/release.sh android
bash Build/release.sh android --debug
bash Build/release.sh android --target play --version-code 2026101701 --version-name 3.0.0
bash Build/release.sh ios
bash Build/release.sh ios --target appstore --version-code 3002 --version-name 3.0.0
bash Build/release.sh macos
bash Build/release.sh macos --debug
bash Build/release.sh macos --version-code 3002 --version-name 3.0.0
bash Build/release.sh macos --target appstore --version-code 3002 --version-name 3.0.0
```

The entry point delegates to the existing platform scripts. Apple App Store export creates an IPA for **manual** Transporter upload only. Play produces an AAB without uploading. Version inputs are mandatory for store targets. F-Droid targets intentionally fail until implemented. macOS App Store archive/export is now implemented provisionally and requires real signing/export validation on a Mac.

**R1 is partial:** full output normalization (Play AAB and iOS IPA now use stable `dist/android/play/` and `dist/ios/appstore/` paths), comprehensive signed distribution validation, macOS App Store signing/export validation on a real Mac, and CI orchestration are still to be implemented. `bash Build/test-release-cli.sh` checks argument validation without invoking Gradle or Xcode. Existing scripts' legacy invocation forms are preserved for compatibility. F-Droid-specific release validation remains B2.

## 2. Target command model

Prefer a small repository-level release entry point, for example:

```text
Build/release.sh android play <versionCode> <versionName>
Build/release.sh android fdroid <versionCode> <versionName>
Build/release.sh ios appstore <buildNumber> <versionName>
Build/release.sh macos appstore <buildNumber> <versionName>
```

The exact file name may change during implementation, but the public contract
should remain narrow and consistent:

- platform;
- distribution target;
- build/version;
- optional output directory;
- no implicit publication unless the command explicitly says `publish`.

The top-level script should delegate to platform-owned scripts rather than
embedding Gradle/Xcode behavior itself.

A preferred shape is:

```text
Build/
  release.sh

android/Build/
  build-app.sh
  prepare-play-release.sh
  prepare-fdroid-release.sh
  publish-fdroid.sh

apple/ios/Build/
  build-app.sh
  archive.sh
  export-appstore.sh

apple/macos/Build/
  build-app.sh
  archive.sh
  export-appstore.sh
```

Names are illustrative; implementation should reuse and rename current scripts
only where that genuinely improves consistency.

## 3. Common release contract

All production release paths should accept explicit versions.

### Android

- `versionCode`: positive integer accepted by Android/Play/F-Droid.
- `versionName`: user-visible release version.

### Apple

- `CFBundleVersion`: explicit monotonically increasing build number.
- `CFBundleShortVersionString`: user-visible release version.
- Host app and embedded extensions must use matching versions.

Release scripts must never silently invent a production version when invoked for
store distribution.

All final scripts should print a concise release summary containing:

- platform/distribution target;
- application/bundle ID;
- version;
- build/version code;
- artifact path;
- signing identity/certificate fingerprint where safe and useful;
- whether publication occurred.

## Android release promotion policy (decision: 18 October 2026)

> **Binding release policy; orchestration still to be implemented.** This policy
> applies to Android/FluxNews releases. It does not imply that B2, F-Droid signing
> continuity, the official F-Droid publication, or the new release workflow have
> already passed acceptance.

**Channel ownership and cadence**

- **GitHub Releases** and **F-Droid** follow the latest *approved* FluxNews
  release. New approved releases must not be held back by Google Play review.
  F-Droid's external build/review queue can introduce a delay after submission.
- **Google Play** is a separate, owner-operated distribution channel. The owner
  chooses when to prepare, upload and publish an AAB. Slow Google review must
  not block GitHub Releases, F-Droid submissions or continued development on
  `main`. Do not automate Play submission/publication.
- One source version and immutable release commit identify the approved release.
  It is acceptable for Play to remain on an older published version and skip
  intermediate GitHub/F-Droid releases. All Android version codes must stay
  compatible with Android's monotonic update rules.

**Required promotion sequence — fail closed**

1. Select an Android release candidate: explicit `versionName`,
   `versionCode`, full source commit SHA and candidate release notes. Treat
   the SHA as immutable for this attempt; do not create the *final* release tag
   or publish a GitHub Release yet.
2. Run the common Android/Rust release checks and **one actual F-Droid
   metadata/scanner/source-build gate against that exact SHA**. The gate must
   produce a nonempty unsigned APK and verify the application ID
   `de.circle_dev.flux_news`, versions, and required native architectures
   (`arm64-v8a`, `x86_64`, `armeabi-v7a`). Reject missing, failed, skipped or
   inconclusive mandatory checks. Reuse existing checks and avoid duplicate
   native builds.
3. Before any first native F-Droid publication, also close B2's dependency
   provenance, reproducibility, historical metadata/signature and
   Flutter-to-native signed-update acceptance criteria. CI success alone does
   **not** establish signing/update compatibility.
4. **Only after all required gates succeed for the same SHA**, create the
   immutable version tag on that tested SHA, publish the corresponding GitHub
   Release and its validated artifacts/release notes, and prepare/submit the
   matching F-Droid recipe referencing that exact tag/SHA. F-Droid submission
   must be explicit and separate from build verification.
5. Official F-Droid infrastructure has its own acceptance/build cycle. A
   successful local or GitHub Actions recipe build is required before GitHub
   publication but does **not** guarantee a successful official F-Droid build.
   Track an external failure explicitly; do not silently change the already
   published tag or its source. Resolve it with a newly tested candidate
   (normally the next patch release), preserving traceability.

**When a candidate fails**

- **No GitHub Release, final tag or F-Droid submission** when any mandatory
  gate fails. Fix the cause on a development/release branch, create a new
  commit/SHA, and rerun *all mandatory gates for that new SHA* before promotion.
  Keep development on `main` independent of any pending store review.
- CI must check the exact commit, expected metadata and actual APK content; a
  workflow marked green with `1 build failed`, or without an APK, is a failure.
- Cost-control: build F-Droid on explicit release validation and focused
  F-Droid changes rather than every documentation-only update. Use path-aware
  triggers, reusable jobs, scoped concurrency/cancellation and **one** recipe
  build per candidate where possible. Do not tie Google Play or Apple jobs to
  the F-Droid gate merely for sequencing.

**Google Play release notes**

- The owner may submit a later approved release directly and omit intervening
  GitHub/F-Droid versions. Generate Play-specific release notes as the
  cumulative *user-relevant* changes since the version **last actually
  published on Google Play**, not since the last GitHub release or an
  unapproved Play submission. Review the combined notes manually before
  uploading the selected signed AAB.
- Review delays, replaced submissions and Managed Publishing do not change the
  identity or readiness of the GitHub/F-Droid source release.

**Implementation status (18 October 2026):** PR
[#66](https://github.com/KevinCFechtel/Flux/pull/66) has a successful
[experimental recipe-build run](https://github.com/KevinCFechtel/Flux/actions/runs/39140681750)
for Android 3.0.0 / `2026101801`, including APK identity/ABI validation.
This proves one CI test build, **not** repeatable official F-Droid eligibility,
historic-signing compatibility or implemented release promotion. PR #66
remains separate from this documentation decision.

### Platform-specific version files (decision: 18 October 2026)

The repository records release versions in **one committed file per platform**:

| File | Application | Keys |
| --- | --- | --- |
| `Build/versions/android.properties` | Android (GitHub, F-Droid, Play) | `VERSION_NAME`, `BUILD_NUMBER` |
| `Build/versions/ios.properties` | iOS/iPadOS | `VERSION_NAME`, `BUILD_NUMBER` |
| `Build/versions/macos.properties` | macOS (App Store, optional Developer ID) | `VERSION_NAME`, `BUILD_NUMBER` |

`VERSION_NAME` is the marketing version; `BUILD_NUMBER` maps to Android
`versionCode` or Apple `CFBundleVersion`. A platform-specific version
change must be reviewed and committed with the intended source changes.
The files start at the previously shared values, `3.0.0` and
`2026101801`, **without declaring any new release or bumping versions**.
They may diverge later as release cycles become independent.

`bash Build/release.sh <platform>` defaults to that platform's committed
file; explicit `--version-code` and `--version-name` together continue to
override it, preserving the existing CLI contract. A missing/incomplete
platform version file is an error, not permission to fall back silently to
another platform. Internal Gradle/Xcode development fallbacks are **not**
production release-version sources.

The eventual release orchestrator reads and validates the requested
platform file(s), their monotonically compatible build numbers and the exact
candidate SHA. It must **not** generate/auto-increment versions or push
version-bump commits during promotion. For `all` releases it additionally
checks that all three `VERSION_NAME` values match; differing numbers imply
separate platform releases. The F-Droid recipe/versionCode and versionName
must agree with the **Android** file, but historical F-Droid entries and
signing fingerprints remain immutable. Do not introduce multiple manually
maintained version authorities in Gradle, Xcode, F-Droid and Actions.

**Implementation state:** The split and CLI selection are being developed
in [PR #66](https://github.com/KevinCFechtel/Flux/pull/66); orchestration
and automated F-Droid recipe generation remain follow-up work. Documenting
this decision does not authorize any tag, store upload, or F-Droid submission.

## 4. Android — Google Play

The current Android build already has a canonical production bundle path through
`android/Build/build-app.sh productionBundle <versionCode> <versionName>`.

Keep that path as the implementation basis, but normalize it behind the shared
release interface.

The Play preparation step must:

- produce the signed production AAB;
- retain application ID `de.circle_dev.flux_news`;
- require explicit versionCode/versionName;
- validate the configured Play upload signing identity;
- verify the resulting bundle/package metadata;
- write the final AAB to a stable `dist/` location;
- never commit signing properties or keystores.

Uploading to Play Console and releasing there are deliberately manual
owner-controlled actions. This repository must prepare/validate a selected
signed Play AAB without automatically submitting or publishing it. The owner
may skip intervening GitHub/F-Droid versions and use consolidated release notes
relative to the last version actually published on Play; see the Android
release promotion policy above.

## 5. Android — F-Droid

A native F-Droid path is still required.

**Prerequisite:** Complete the reproducible source-build and scanner feasibility gate B2 in [POST_REPLACEMENT_FOLLOWUP_PLAN.md](POST_REPLACEMENT_FOLLOWUP_PLAN.md) before implementing the publication workflow. Pinned Cargo-derived AARs and JNA require provenance/build checks; scanner failure has not yet been established.

The repository must gain both:

1. canonical local F-Droid release preparation; and
2. a GitHub Action that builds and publishes/submits the native F-Droid release
   using the same underlying scripts.

The new F-Droid path must replace the old Flutter-repository distribution
ownership only after the native path is validated.

Requirements:

- preserve the existing F-Droid application/package identity;
- keep F-Droid signing independent from Google Play signing;
- support the architectures accepted for the native release;
- be reproducible and compatible with F-Droid's build constraints;
- avoid hidden network/bootstrap steps that make source builds non-reproducible;
- prepare/update native F-Droid metadata from the development `Flux` source
  for pre-cutover testing, then from the release source in `FluxNews` after migration;
- validate a signed in-place update over the existing Flutter F-Droid variant;
- retain old Flutter F-Droid metadata/releases until native update compatibility
  is proven;
- make secrets/signing inputs GitHub Actions secrets or local ignored files,
  never repository content.

### F-Droid GitHub Actions

Add a dedicated workflow, for example
`.github/workflows/fdroid.yml`.

It should have two clearly separated responsibilities:

- **build/verify:** reproducible native F-Droid artifact + metadata validation;
- **publish/submit:** explicit release/manual/tag-triggered submission step after
  build/verify succeeds.

Do not make every push to `main` publish an F-Droid release. The
F-Droid recipe/source-build job is a **required, blocking pre-release gate**
for GitHub publication, not a best-effort post-release check. Its workflow must
allow explicit candidate-SHA validation *before* the final tag exists.

Prefer `workflow_dispatch` and/or deliberate release-candidate triggering
with explicit version inputs, a fixed commit SHA and a reusable build/verify
job. Publishing/submitting the F-Droid recipe is a separate explicit action
**after** promotion of the previously validated SHA. No GitHub Release or tag
may be created first and then retroactively "validated".

The Action must call repository scripts. It must not contain a second independent
implementation of signing, versioning or packaging logic in YAML.

## 6. iOS — App Store Connect / Transporter

The primary iOS distribution remains the App Store.

Current building blocks already exist:

- `apple/ios/Build/build-app.sh`;
- `apple/ios/Build/archive.sh`;
- `apple/ios/Build/export-appstore.sh`.

These should be normalized into the common release model.

The final iOS App Store release path should:

- build the production configuration;
- archive the app;
- validate the production bundle identifier;
- validate the Widget extension identifier;
- validate App Group entitlements;
- validate host/extension version equality;
- export an App Store Connect-compatible IPA;
- place it in a predictable `dist/` directory;
- clearly report that the IPA is ready for Transporter/manual App Store Connect
  upload.

Rename `export-appstore.sh` to a more accurate App Store-oriented name if the
implementation confirms that it is a general `app-store-connect` export rather
than TestFlight-specific behavior. Preserve compatibility temporarily if other
automation already calls the old name.

### iOS CI artifact builds

GitHub Actions may optionally create unsigned or appropriately signed release
artifacts for verification/download when credentials are available.

That is supplementary. The primary production-distribution workflow should
remain:

```text
local/canonical release script
→ signed Xcode archive
→ validated App Store Connect IPA
→ Transporter/App Store Connect
→ TestFlight/App Store release
```

CI should never require storing broad Apple developer credentials merely to
replace a reliable Transporter-based release process.

## 7. macOS — App Store Connect / Transporter

**Implementation/acceptance distinction (16 October 2026):** PR #38
implemented host Sandbox entitlements and sandbox-local media storage, and
PR #53 added signed-development-build verification and safe local installation.
C3.1–C3.7 are now implemented and merged; C3.8 and the **separate B1 signed
fresh-container runtime acceptance are still open**. [Apple CI #167](https://github.com/KevinCFechtel/Flux/actions/runs/38934397341)
passed on the combined `main`, but does not close B1. Finish
[MACOS_SANDBOX_ACCEPTANCE.md](MACOS_SANDBOX_ACCEPTANCE.md) **before implementing**
the Mac App Store archive/export deliverable. That later Store export is part
of R, not part of the B1 runtime sign-off.

The primary macOS distribution should likewise be the Mac App Store.

**Mac release prerequisite and approved decision:** The macOS app has **never been released**. Its host App Sandbox entitlement has been implemented but signed-app acceptance is still outstanding. The existing Developer ID/notarization path is not a Mac App Store export. Validate host Sandbox, outbound network access, actual file-dialog capabilities and App Group provisioning **before** Mac App Store archive/export scripting. The developer explicitly accepts losing all existing unsandboxed local development data on their machine. Initialize a fresh sandbox storage/credential environment: **no database/download/Keychain migration, `container-migration.plist`, legacy-location fallback or compatibility layer is required**. See B1 in [POST_REPLACEMENT_FOLLOWUP_PLAN.md](POST_REPLACEMENT_FOLLOWUP_PLAN.md).

The existing `apple/macos/Build/build-app.sh` is currently a build/validation
script, not a complete App Store distribution path.

Add macOS equivalents to the iOS archive/export flow.

The final macOS App Store path should:

- use the production Xcode configuration;
- build/archive the host app and Widget extension;
- validate the already-implemented Sandbox, outbound network/user-selected-file permissions and host/widget App Group provisioning **in the final Mac App Store-signed artifact**;
- use the correct Mac App Store distribution signing/provisioning;
- apply explicit app/extension build and marketing versions;
- validate bundle identifiers and embedded extension metadata;
- export an App Store Connect-compatible artifact accepted by Transporter;
- place the final artifact in a predictable `dist/` directory;
- perform no upload unless explicitly requested.

The desired primary flow is:

```text
local/canonical release script
→ signed macOS archive
→ validated App Store Connect export
→ Transporter/App Store Connect
→ Mac App Store
```

As on iOS, GitHub Actions may optionally build release artifacts, but the App
Store remains the primary distribution channel.

## 8. Apple script convergence

iOS and macOS should share conventions even when their Xcode export mechanics
differ.

Align at least:

- positional/flag version inputs;
- `--help` output;
- output directory conventions;
- archive naming;
- release summaries;
- validation style;
- fail-fast handling;
- no-publish-by-default behavior.

Prefer shared shell helpers only for genuinely identical logic such as version
validation or common output formatting. Do not create a large cross-platform
shell abstraction that obscures Xcode target-specific signing or entitlement
requirements.

## 9. GitHub Actions strategy

Keep CI and distribution separate.

Existing canonical Android/Apple regression workflows remain the merge gate.

Add release-oriented workflows only where they provide value:

- Android F-Droid build/publish: required;
- Android Play release artifact: optional;
- iOS App Store artifact: optional;
- macOS App Store artifact: optional.

For Android, the release candidate / GitHub promotion workflow must
depend on a verified F-Droid recipe APK from the **same commit**, and create
the final tag/GitHub Release only after this gate passes. Google Play
preparation/submission remains optional and owner-controlled; it cannot
delay an otherwise approved GitHub/F-Droid release.

### Repository migration and release ownership (decision: 18 October 2026)

**The release system moves to FluxNews at cutover; it is not permanently
split across two repositories.** Distinguish the temporary development
repository from the permanent product/release repository:

| Stage | Code / routine CI | Release orchestration and GitHub Releases |
| --- | --- | --- |
| Before cutover | [`Flux`](https://github.com/KevinCFechtel/Flux): native implementation, scripts, focused CI and B2 feasibility testing | New release workflow is **not active**; no native tags, F-Droid submission or GitHub publication |
| Cutover | Import native sources into existing [`FluxNews`](https://github.com/KevinCFechtel/FluxNews), archive prior Flutter tree in `legacy/`, replace legacy workflows with new workflows | **No release** as a side effect of import |
| After cutover | `FluxNews`: further code changes, PRs and routine CI | **Exclusively `FluxNews`**: release dispatch, candidate validation, platform/F-Droid gates, final tags and public GitHub Releases |

The `Flux` repository may remain online, but **must not be a permanent
release controller or publish releases into FluxNews**. The existing
`FluxNews` repository identity, stars, issues/comments, discussions,
historical Flutter releases/tags and their Git history remain intact. Do
not overwrite or force-replace the existing Git history.

**The import commit is not the release commit**

1. Import the native source tree and scripts from `Flux` into a reviewable
   branch/commit in `FluxNews`. Move the previous Flutter implementation
   into `legacy/`, preserving historical releases and Git tags. Record
   the `Flux` source SHA and `FluxNews` import SHA for traceability.
2. At the same cutover, **replace** the legacy GitHub Actions workflows in
   `FluxNews` with the new normal CI and release workflow definitions.
   Retire the Flutter `.github/workflows/build-and-release.yml`
   (`on.push.tags: v*`) and its `submit-fdroid-signatures.yml`
   chain before any native tag is pushed. Merely moving those files into
   `legacy/` does not make the old trigger safe. The replacements must
   not create a tag/release, run unnecessary duplicate jobs, or submit an
   official F-Droid update during migration.
3. After the import, **continue normal development in `FluxNews`**. Any
   number of subsequent commits are expected for bugs, tests, workflows,
   translations and release preparation. No release tag or full release
   gate is required for the initial import or every ordinary later commit.
4. Only when the owner requests a release, run the `workflow_dispatch`
   orchestrator **in FluxNews** with scope (`android`, `ios`, `macos`,
   `all`), its committed platform versions and the **final immutable
   FluxNews release-candidate SHA**. A preceding `Flux` or import SHA
   is *not* the release source. The native tree may have changed since
   import; do not require it to match the original Flux snapshot.
5. Run all mandatory selected gates against **that final FluxNews SHA**.
   For Android this includes the F-Droid recipe/source-APK verification.
   If the SHA changes during later fixes or merges, the final candidate
   requires new mandatory gate results. Only on success may `FluxNews`
   create its own immutable platform/common tags and **one** corresponding
   GitHub Release. The import step itself never authorizes publication.
6. The new release workflow in `FluxNews` needs only appropriately
   scoped permissions within **that repository** (for example,
   `contents: write` on the promotion job), not an external GitHub App
   token for cross-repository release publishing. Keep signing credentials
   restricted and never expose them to PR/test jobs.

**F-Droid and compatibility at cutover:** The current experimental B2
metadata still points its `Repo` field to `Flux.git`. Adapt the native
build recipe to the final `FluxNews` source and actual future release SHA
while keeping all historical Flutter recipes, release tag/commit
resolvability, historical APK signing fingerprints and signed-upgrade
requirements intact. `FluxNews` must remain the official update source
after cutover. No official F-Droid submission is authorized by migration
or by a passing F-Droid CI source-build gate.

**Distribution remains separately controlled:** Google Play publication
and iOS/macOS uploads through Transporter/App Store Connect are manual;
they need not align with the GitHub/F-Droid release cadence. The
architecture can be developed and validated in Flux before migration,
but **every active production release workflow and its execution belong
to FluxNews after migration**. This is a documented target, not a claim
that cutover, release automation or native publication has occurred.

### Hybrid platform tags and selective CI gates (decision: 18 October 2026)

> **Pre-cutover implementation under validation (19 October 2026).** PR #81
> implements this contract in **Flux** so the release workflow can be exercised
> before repository cutover. GitHub Releases created in Flux are explicitly
> allowed for this validation. This does not change eventual FluxNews release
> ownership and does not authorize Store publication or official F-Droid submission.

After the cutover, FluxNews owns development, CI, release orchestration
and all GitHub Releases; Flux is not a release controller. The release
cycles for Android, iOS/iPadOS and macOS remain independent.
A manual release-candidate workflow in FluxNews (proposed
`workflow_dispatch`) takes `scope` (`android`, `ios`, `macos`, or
`all`), `versionName`, the **full immutable Git commit SHA**, and the
applicable platform build/version codes. Resolve these inputs up front;
never silently test the current tip of `main` instead.

| Scope | Required checks before any final tag | Final tags | GitHub Release |
| --- | --- | --- | --- |
| `android` | Android + Rust + **mandatory F-Droid source build, scanner, APK verification** | `android/vX.Y.Z` | One Android entry |
| `ios` | iOS + Rust | `ios/vX.Y.Z` | One iOS entry |
| `macos` | macOS + Rust (including relevant Sandbox/signing checks) | `macos/vX.Y.Z` | One macOS entry |
| `all` | Android + F-Droid + iOS + macOS + **Rust once** | `android/vX.Y.Z`, `ios/vX.Y.Z`, `macos/vX.Y.Z`, `vX.Y.Z` | **One combined entry** |

Each platform may have a different public version and release date. A
combined `vX.Y.Z` release is allowed **only if all three platforms have
exactly the same approved marketing version and tested commit SHA**. Its
three platform tags and the combined tag all point to that SHA. Only
`vX.Y.Z` gets a GitHub Release entry; the additional platform tags are
provenance markers, not three more release pages. If versions or source
commits differ, publish individually. Two-platform releases remain separate
unless grouping is explicitly designed later.

**Mandatory sequence:**

1. Select the scope/version/immutable source SHA and draft platform-specific
   notes. **No final release tag and no public GitHub Release exist yet.**
2. Reuse the existing Android/iOS/macOS build/test scripts via separate
   callable gates (`workflow_call` or equivalent). Run only selected
   platforms and the Rust workspace regression tests **once per candidate**;
   do not cascade full workflows or duplicate native compilation.
3. For an `android` or `all` candidate, the F-Droid recipe lint/scanner
   and real source-built APK identity/version/ABI checks are **blocking before
   any GitHub release**. The CI APK is unsigned test evidence, not an
   installable end-user release. Signing/update compatibility (B2) must be
   approved separately before any official F-Droid submission.
4. If any mandatory check is missing, skipped, inconclusive or failed, stop
   without final tags, GitHub release, store upload or F-Droid submission.
   Correct on a branch, then rerun all required gates for the **new** SHA.
5. After every mandatory gate passes at the **same SHA**, a dedicated,
   minimally permissioned promotion job verifies that tags and release names
   do not already conflict; only then create the intended immutable tag(s)
   and **exactly one** GitHub Release with the right notes and assets.
   Never silently move an existing public tag. Partial promotion must be
   detected and recovered explicitly.
6. Apple Store exports/uploads and Google Play uploads/publication remain
   owner-controlled, independent of GitHub release timing. F-Droid submission
   is a separate explicitly authorized action; no official F-Droid release
   or submission is permitted until B2 publication acceptance and owner
   approval.

**GitHub Release presentation and downloads:**

- Clearly name the covered platform(s). A combined release has separate
  Android, iOS/iPadOS and macOS sections of release notes.
- Android may attach only a correctly **signed and verified** distributable
  APK, never the unsigned F-Droid CI test output.
- iOS/iPadOS has release notes and an App Store link, not a generic IPA
  download. macOS has notes and a Mac App Store link; an optional ZIP
  must first pass Developer ID signing, notarization and update-path review.
- GitHub's `Latest` is repository-wide, not per platform. Maintain a
  separate per-platform latest-version overview (e.g. in README).

**CI invocation and cost controls:**

- Existing PR/path-filtered Android/Apple/Rust checks remain in place for
  development. The manual candidate orchestrator reuses them selectively;
  docs-only changes must not start expensive F-Droid or Apple builds.
- Tags are created *after* the gates. Tag-push events may trigger only
  post-promotion bookkeeping, **not** the blocking checks. Multiple tags
  on a common commit must not cause repeated CI or extra Releases; do not
  depend on separate push events being emitted for every tag.
- Use candidate-scoped concurrency and cancellation, with artifacts tied to
  commit SHA/scope/version. Do not launch duplicate Rust or F-Droid builds.
  Only the final publisher needs `contents: write`; ordinary checks
  remain read-only and hold no store publishing credentials.

**Implementation validation status (19 October 2026):** PR #81 provides the
manual scoped orchestrator, full-SHA/version preflight, selective platform gates,
the mandatory Android F-Droid source-build path, developer signing verification,
multi-tag/single-release promotion, and cheap workflow/contract validation.
It remains unaccepted until those checks are green and controlled `validate`
and `release` dispatches have been exercised from `main`. Official F-Droid
submission and the FluxNews cutover remain separate later steps.

Release workflows should generally be manual or release/tag-driven and should:

- call the same canonical scripts used locally;
- surface artifacts for inspection when appropriate;
- use environment/secret protection for signing credentials;
- never publish from arbitrary pull requests;
- never silently derive a production signing identity from development config.

## 10. Implementation order

Implement in this order:

1. **Define common version/CLI conventions.**
   Document exact argument names and artifact paths before changing platform
   scripts.

2. **Normalize Android Play preparation.**
   Wrap the existing production AAB flow without changing its signing model.

3. **Validate F-Droid build/scanner feasibility, then implement native preparation.**
   Complete B2 in `POST_REPLACEMENT_FOLLOWUP_PLAN.md` first. Port only the still-
   required metadata/signing/reproducibility behavior from the old Flutter repository.

4. **Add Android F-Droid build/publish GitHub Action.**
   Make it call the canonical scripts and validate update compatibility before
   retiring old Flutter distribution automation.

5. **Normalize iOS archive/export.**
   Convert the existing archive + App Store Connect export path to the shared
   release interface and rename TestFlight-specific naming where appropriate.

6. **Enable and validate the macOS sandbox, then add macOS archive/export.**
   Complete B1 in `POST_REPLACEMENT_FOLLOWUP_PLAN.md` first, with fresh developer
   data (no migration), and only then create the missing App Store Connect/
   Transporter path with proper Mac App Store signing and entitlement validation.

7. **Optionally add Apple release-artifact workflows.**
   Only after local scripts are authoritative and stable.

8. **Final release smoke/documentation pass.**
   Verify `--help`, versioning, paths, signing failure modes and produced
   artifacts for all four targets: Play, F-Droid, iOS App Store and macOS App
   Store.

## 11. Definition of done

This release-scripting follow-up is complete when:

- one documented top-level interface can prepare each supported distribution
  target;
- Android Play AAB preparation is deterministic and versioned;
- the manual release entry point selects `android`, `ios`, `macos` or `all` gates by immutable candidate SHA, running shared Rust checks only once;
- platform tags produce their independent release pages, while all-platform releases create a common tag and exactly one combined GitHub Release;
- migration imports the native app into the existing `FluxNews` repository without publishing, replaces the old Flutter workflows, preserves historic tags/community history, and allows further development commits before selecting the final release SHA;
- after migration `FluxNews` alone hosts the CI, release orchestration and final GitHub Releases; `Flux` has no permanent release-publishing role;
- every Android GitHub Release is blocked until the F-Droid metadata/scanner/real-APK build and shared mandatory checks pass for the exact candidate SHA;
- a failed release candidate cannot create a final tag or GitHub Release, and fixes are retested at a new SHA;
- the F-Droid-style source build and scanner feasibility checks pass before publishing is automated;
- Android has a native F-Droid build/publish workflow in this repository;
- F-Droid update compatibility over the existing Flutter-distributed app is
  validated;
- iOS can produce a validated production App Store Connect IPA for Transporter;
- the previously unreleased macOS app passes a fresh-install sandbox acceptance without migrating local development data;
- macOS can produce a validated Mac App Store Connect artifact for Transporter;
- Apple host apps and extensions are version/signing/entitlement checked;
- optional CI artifact jobs delegate to the same local scripts;
- no production release path publishes implicitly;
- the primary Apple release path remains App Store Connect/Transporter;
- replacement/product implementation remains untouched.

## 12. Non-goals

This follow-up does not:

- change application functionality;
- reopen migration logic;
- change Core/UniFFI architecture;
- replace Play/App Store/F-Droid with GitHub Releases;
- require fully automatic store publication;
- move production secrets into the repository;
- make CI-produced artifacts the authoritative release source when the canonical
  local script produced and validated the final signed store artifact.

## R2 macOS App Store export implementation (17 October 2026)

`bash Build/release.sh macos --target appstore --version-code N --version-name V` invokes `apple/macos/Build/archive.sh` and `export-appstore.sh`. The archive uses the Release configuration, explicit host/widget version settings, automatic provisioning and Apple Distribution signing; `verify-sandbox.sh ... distribution` checks the signed host/widget bundle IDs, version parity, Sandbox and App Group entitlements, signature chain and Apple Distribution team. Export uses Xcode's App Store Connect export method, expects a non-empty `.pkg` in `dist/macos/appstore/`, and never uploads automatically.

**Not yet accepted:** This flow has not been exercised with the owner's Apple Distribution certificates/profiles or Transporter. Xcode/macOS export compatibility, provisioning, App Group and embedded Rust library signing must be validated on the owner's Mac before calling R2 complete. Store signing credentials must remain outside Git.

## R1 version argument parity

The central `Build/release.sh` accepts `--version-code` and `--version-name` for normal and store builds on Android, iOS and macOS. For Apple, `--version-code` maps to `CFBundleVersion` / `CURRENT_PROJECT_VERSION` and `--version-name` to `CFBundleShortVersionString` / `MARKETING_VERSION`. Normal builds may omit both and use the project values; store release targets require both. The macOS direct build script accepts `--build-number N --version-name V` and passes both to Xcode, affecting app and widget targets. The iOS direct build and archive scripts already support equivalent version inputs; export scripts inherit the archived version. This is a CLI contract change, not a claim of device/store acceptance.

## macOS local installation default

`apple/macos/Build/install-local.sh` now defaults to strict `developer-id` verification, requiring a Developer ID Application signed host, widget and embedded Rust library with matching team, Sandbox and App Group entitlements. By default, the newest Developer ID ZIP in `dist/macos/developer-id/` is extracted and installed. Set `SOURCE_APP=/path/to/FluxNews.app` to select an unpackaged app explicitly. For deliberate development-only installs, `INSTALL_MODE=development` opts into the prior Apple Development/provisioning verification. Note that the ordinary `macos` build and App Store archive do **not** produce a Developer ID signed app: use `apple/macos/Build/release-developer-id.sh` (Developer ID signing/notarization pipeline) before the default local installation. The Developer ID release pipeline still has its own environment/signing prerequisites.

## R cleanup: distribution entry points

The former iOS `export-testflight.sh` has been replaced by `apple/ios/Build/export-appstore.sh`; the former macOS `release.sh` is now `apple/macos/Build/release-developer-id.sh`. Both former files have been deleted. The central `Build/release.sh` delegates to these named distribution scripts; for a notarized Developer ID ZIP run `bash Build/release.sh macos --target developer-id [--version-code N --version-name V]`. The Developer ID script accepts explicit version overrides, and its output is `dist/macos/developer-id/`; the newest notarized ZIP in `dist/macos/developer-id/` is the default source for `install-local.sh`. App Store and Developer ID are distinct signing/distribution channels. External automation using the old paths must be updated.

The cleanup is not a claim of release acceptance: validate CI and run the Apple signing/notarization/export workflows on the owner's Mac before merging.

## macOS distribution artifact layout

The macOS unpackaged app and both distribution artifacts live under `dist/macos/`:

- `dist/macos/FluxNews.app`: unpackaged app from macOS build; the Developer ID release signs and notarizes this app.

- `dist/macos/appstore/*.pkg`: Mac App Store Connect package for Transporter (unchanged).
- `dist/macos/developer-id/FluxNews-<version>-macos-<architecture>.zip`: notarized Developer ID ZIP (moved from `dist/release/`).

By default `install-local.sh` extracts the newest Developer ID ZIP from `dist/macos/developer-id/` and installs its verified app; `SOURCE_APP` can still select an unpackaged app explicitly; existing ZIP files in the legacy `dist/release/` directory and the former `dist/FluxNews.app` are not automatically moved or removed. Re-run the Developer ID release to create an artifact in the new directory.
